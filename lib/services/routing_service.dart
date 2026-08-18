import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/route_result.dart';
import '../utils/app_logger.dart';
import '../utils/polyline_codec.dart';
import 'app_settings_service.dart';
import 'map_tile_store.dart';

/// Directions from our self-hosted Valhalla instance, cached locally.
///
/// Every request checks [MapTileStore] first, so a route already asked for is
/// redrawn with no network at all — which matters for a device that spends its
/// time out of coverage. Responses are stored in the form Valhalla sends them:
/// the shape stays an encoded polyline (roughly a tenth the size of coordinate
/// pairs) and the maneuvers are gzipped JSON.
class RoutingService extends ChangeNotifier {
  RoutingService({required this.appSettingsService, required this.store});

  final AppSettingsService appSettingsService;
  final MapTileStore store;

  static const String _logTag = 'RoutingService';
  static const Duration _timeout = Duration(seconds: 20);

  RouteResult? _route;
  bool _isRouting = false;
  String? _lastError;

  RouteResult? get route => _route;
  bool get isRouting => _isRouting;
  String? get lastError => _lastError;

  /// Polyline vertices for the map layer; empty when no route is shown.
  List<LatLng> get routePoints => _route?.points ?? const [];

  void clearRoute() {
    if (_route == null) return;
    _route = null;
    _lastError = null;
    notifyListeners();
  }

  /// Identifies a request for cache purposes.
  ///
  /// Coordinates are rounded to microdegrees first, so two taps a few
  /// centimetres apart reuse one route instead of filling the cache with
  /// near-duplicates.
  @visibleForTesting
  static Uint8List requestHash({
    required LatLng from,
    required LatLng to,
    required String costing,
  }) {
    String e6(double v) => (v * 1e6).round().toString();
    final key =
        '$costing|${e6(from.latitude)},${e6(from.longitude)}'
        '|${e6(to.latitude)},${e6(to.longitude)}';
    return Uint8List.fromList(md5.convert(utf8.encode(key)).bytes);
  }

  /// Routes [from] -> [to], preferring the local cache.
  ///
  /// Set [forceRefresh] to bypass the cache and re-ask the server.
  Future<RouteResult?> route$({
    required LatLng from,
    required LatLng to,
    String costing = 'auto',
    bool forceRefresh = false,
  }) async {
    if (_isRouting) return _route;
    _isRouting = true;
    _lastError = null;
    notifyListeners();

    final hash = requestHash(from: from, to: to, costing: costing);
    try {
      if (!forceRefresh) {
        final cached = await _fromCache(hash);
        if (cached != null) {
          _route = cached;
          return _route;
        }
      }
      final fetched = await _fromServer(
        from: from,
        to: to,
        costing: costing,
        hash: hash,
      );
      _route = fetched;
      return _route;
    } catch (e) {
      _lastError = '$e';
      appLogger.error('routing failed: $e', tag: _logTag);
      return null;
    } finally {
      _isRouting = false;
      notifyListeners();
    }
  }

  Future<RouteResult?> _fromCache(Uint8List hash) async {
    try {
      final c = await store.getRoute(hash);
      if (c == null) return null;
      final maneuvers = <RouteManeuver>[];
      final blob = c.maneuvers;
      if (blob != null && blob.isNotEmpty) {
        final list = jsonDecode(utf8.decode(gzip.decode(blob))) as List;
        for (final m in list) {
          maneuvers.add(RouteManeuver.fromJson(m as Map<String, dynamic>));
        }
      }
      return RouteResult(
        points: PolylineCodec.decode(c.shape),
        distanceMetres: c.distanceMetres,
        durationSeconds: c.durationSeconds,
        maneuvers: maneuvers,
        costing: c.costing,
        fromCache: true,
      );
    } catch (e) {
      // A corrupt cache entry must not block routing — fall through to the
      // network and overwrite it.
      appLogger.error('cached route unreadable: $e', tag: _logTag);
      return null;
    }
  }

  Future<RouteResult> _fromServer({
    required LatLng from,
    required LatLng to,
    required String costing,
    required Uint8List hash,
  }) async {
    final base = appSettingsService.settings.routingUrl.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final resp = await http
        .post(
          Uri.parse('$base/route'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'locations': [
              {'lat': from.latitude, 'lon': from.longitude},
              {'lat': to.latitude, 'lon': to.longitude},
            ],
            'costing': costing,
            // Metric throughout; the UI converts for display.
            'directions_options': {'units': 'kilometers'},
          }),
        )
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw HttpException('routing server returned ${resp.statusCode}');
    }
    final parsed = parseResponse(resp.body, costing: costing);

    // Store what the server actually sent, not the decoded form.
    final legs =
        (jsonDecode(resp.body)['trip']['legs'] as List).cast<Map<String, dynamic>>();
    await store.putRoute(
      requestHash: hash,
      costing: costing,
      fromLat: from.latitude,
      fromLon: from.longitude,
      toLat: to.latitude,
      toLon: to.longitude,
      distanceMetres: parsed.distanceMetres,
      durationSeconds: parsed.durationSeconds,
      shape: legs.map((l) => l['shape'] as String).join(),
      maneuvers: parsed.maneuvers.isEmpty
          ? null
          : Uint8List.fromList(
              gzip.encode(
                utf8.encode(
                  jsonEncode([for (final m in parsed.maneuvers) m.toJson()]),
                ),
              ),
            ),
    );
    return parsed;
  }

  /// Parses a Valhalla `/route` response.
  ///
  /// Exposed for tests so the wire contract can be pinned against a real
  /// response without a live server.
  @visibleForTesting
  static RouteResult parseResponse(String body, {required String costing}) {
    final trip = jsonDecode(body)['trip'] as Map<String, dynamic>;
    final legs = (trip['legs'] as List).cast<Map<String, dynamic>>();

    final points = <LatLng>[];
    final maneuvers = <RouteManeuver>[];
    for (final leg in legs) {
      // Shape indices are per-leg, so they shift by however many points came
      // before this leg.
      final offset = points.length;
      points.addAll(PolylineCodec.decode(leg['shape'] as String));
      for (final m in (leg['maneuvers'] as List? ?? const [])) {
        final mm = m as Map<String, dynamic>;
        maneuvers.add(
          RouteManeuver(
            instruction: mm['instruction'] as String? ?? '',
            // Valhalla reports leg length in the requested units (km here).
            distanceMetres: (((mm['length'] as num?) ?? 0) * 1000).round(),
            durationSeconds: ((mm['time'] as num?) ?? 0).round(),
            beginShapeIndex:
                offset + (((mm['begin_shape_index'] as num?) ?? 0).toInt()),
          ),
        );
      }
    }

    final summary = trip['summary'] as Map<String, dynamic>;
    return RouteResult(
      points: points,
      distanceMetres: (((summary['length'] as num?) ?? 0) * 1000).round(),
      durationSeconds: ((summary['time'] as num?) ?? 0).round(),
      maneuvers: maneuvers,
      costing: costing,
    );
  }
}
