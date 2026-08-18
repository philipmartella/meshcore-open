import 'package:latlong2/latlong.dart';

/// One step of turn-by-turn guidance.
class RouteManeuver {
  final String instruction;
  final int distanceMetres;
  final int durationSeconds;

  /// Index into [RouteResult.points] where this maneuver begins.
  final int beginShapeIndex;

  const RouteManeuver({
    required this.instruction,
    required this.distanceMetres,
    required this.durationSeconds,
    required this.beginShapeIndex,
  });

  Map<String, dynamic> toJson() => {
    'i': instruction,
    'd': distanceMetres,
    't': durationSeconds,
    'b': beginShapeIndex,
  };

  /// Short keys because these are gzipped and stored by the thousand; the
  /// field names would otherwise outweigh the values.
  factory RouteManeuver.fromJson(Map<String, dynamic> j) => RouteManeuver(
    instruction: j['i'] as String? ?? '',
    distanceMetres: (j['d'] as num?)?.toInt() ?? 0,
    durationSeconds: (j['t'] as num?)?.toInt() ?? 0,
    beginShapeIndex: (j['b'] as num?)?.toInt() ?? 0,
  );
}

/// A computed route, from the routing server or replayed from the cache.
class RouteResult {
  final List<LatLng> points;
  final int distanceMetres;
  final int durationSeconds;
  final List<RouteManeuver> maneuvers;
  final String costing;

  /// True when this came from the local store rather than the network.
  final bool fromCache;

  const RouteResult({
    required this.points,
    required this.distanceMetres,
    required this.durationSeconds,
    required this.maneuvers,
    required this.costing,
    this.fromCache = false,
  });

  double get distanceKm => distanceMetres / 1000;
  Duration get duration => Duration(seconds: durationSeconds);

  RouteResult asCached() => RouteResult(
    points: points,
    distanceMetres: distanceMetres,
    durationSeconds: durationSeconds,
    maneuvers: maneuvers,
    costing: costing,
    fromCache: true,
  );
}
