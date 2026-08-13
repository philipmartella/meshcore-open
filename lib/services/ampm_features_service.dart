import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/ampm_features.dart';
import '../utils/app_logger.dart';

/// Talks the Martellaville AMPM firmware fork's custom companion commands
/// (FlockYou detector + GPS track logger, codes 0xF0-0xF7) and holds the
/// last-fetched results for the map overlays to render.
///
/// The connector has no dedicated handler for these codes — it sends whatever
/// bytes we hand [MeshCoreConnector.sendFrame] and re-broadcasts every inbound
/// frame (including ones its own switch drops) on
/// [MeshCoreConnector.receivedFrames]. So each request is: subscribe to the
/// stream, send the command, await the matching response code, unsubscribe.
/// Requests are issued one at a time (each awaited before the next), so at most
/// one custom command is ever in flight and response correlation by code alone
/// is unambiguous.
class AmpmFeaturesService extends ChangeNotifier {
  AmpmFeaturesService(this._connector) {
    _connector.addListener(_onConnectorChanged);
  }

  final MeshCoreConnector _connector;

  static const String _logTag = 'AmpmFeaturesService';
  static const Duration _defaultTimeout = Duration(seconds: 6);

  // ── FlockYou state ──────────────────────────────────────────────────────
  // Both the raw list and the mappable subset are stored (not computed on
  // read) so their references stay stable between fetches — the map layer uses
  // context.select on flockYouDetectionsWithLocation and must not rebuild on
  // every progress notification.
  List<FlockYouDetection> _flockYouDetections = const [];
  List<FlockYouDetection> _flockYouWithLocation = const [];
  bool _isLoadingFlockYou = false;
  DateTime? _flockYouFetchedAt;

  List<FlockYouDetection> get flockYouDetections => _flockYouDetections;
  bool get isLoadingFlockYou => _isLoadingFlockYou;
  DateTime? get flockYouFetchedAt => _flockYouFetchedAt;

  /// Detections that carry a valid GPS fix (the only ones that can be mapped).
  List<FlockYouDetection> get flockYouDetectionsWithLocation =>
      _flockYouWithLocation;

  // ── GPS track state ─────────────────────────────────────────────────────
  List<GpsFix> _gpsTrackFixes = const [];
  List<LatLng> _gpsTrackPoints = const [];
  GpsTrackStatus? _gpsTrackStatus;
  bool _isLoadingGpsTrack = false;
  double? _gpsDownloadProgress; // 0..1 while paging chunks
  DateTime? _gpsTrackFetchedAt;

  List<GpsFix> get gpsTrackFixes => _gpsTrackFixes;
  GpsTrackStatus? get gpsTrackStatus => _gpsTrackStatus;
  bool get isLoadingGpsTrack => _isLoadingGpsTrack;
  double? get gpsDownloadProgress => _gpsDownloadProgress;
  DateTime? get gpsTrackFetchedAt => _gpsTrackFetchedAt;

  /// Track polyline vertices in fix order (stable reference between fetches).
  List<LatLng> get gpsTrackPoints => _gpsTrackPoints;

  String? _lastError;
  String? get lastError => _lastError;

  // ── Connection lifecycle ────────────────────────────────────────────────
  void _onConnectorChanged() {
    // Stale detections/track from a previous device must not linger on the map.
    if (!_connector.isConnected &&
        (_flockYouDetections.isNotEmpty || _gpsTrackFixes.isNotEmpty)) {
      _flockYouDetections = const [];
      _flockYouWithLocation = const [];
      _gpsTrackFixes = const [];
      _gpsTrackPoints = const [];
      _gpsTrackStatus = null;
      _flockYouFetchedAt = null;
      _gpsTrackFetchedAt = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _connector.removeListener(_onConnectorChanged);
    super.dispose();
  }

  // ── Request/response primitive ──────────────────────────────────────────

  /// Sends [cmd] and awaits the first inbound frame whose leading byte is
  /// [respCode]. Returns the response frame, or null on timeout / ERR / not
  /// connected. Subscribes before sending so a fast response is never missed.
  Future<Uint8List?> _sendAndAwait(
    Uint8List cmd,
    int respCode, {
    Duration timeout = _defaultTimeout,
  }) async {
    if (!_connector.isConnected) return null;
    final completer = Completer<Uint8List?>();
    final sub = _connector.receivedFrames.listen((frame) {
      if (frame.isEmpty || completer.isCompleted) return;
      if (frame[0] == respCode) {
        completer.complete(frame);
      } else if (frame[0] == respCodeErr) {
        // Firmware rejected the command (e.g. feature disabled / old build).
        completer.complete(null);
      }
    });
    try {
      await _connector.sendFrame(cmd);
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (e) {
      appLogger.error('sendAndAwait failed: $e', tag: _logTag);
      return null;
    } finally {
      await sub.cancel();
    }
  }

  // ── FlockYou ────────────────────────────────────────────────────────────

  /// Pages the whole detection table off the device (CMD_FLOCKYOU_LIST_CHUNK).
  Future<void> fetchFlockYouDetections() async {
    if (_isLoadingFlockYou) return;
    _isLoadingFlockYou = true;
    _lastError = null;
    notifyListeners();
    try {
      final out = <FlockYouDetection>[];
      int idx = 0;
      // Guard against a misbehaving device looping forever. Detection index is
      // a single byte on the wire (idx & 0xFF), so the table is capped at 255.
      for (int page = 0; page < 512; page++) {
        final cmd = Uint8List.fromList([cmdFlockYouListChunk, idx & 0xFF]);
        final resp = await _sendAndAwait(cmd, respCodeFlockYouListChunk);
        if (resp == null || resp.length < 3) break;
        final r = BufferReader(resp);
        r.skipBytes(1); // response code
        final returned = r.readUInt8();
        final hasMore = r.readUInt8() != 0;
        // A truncated BLE frame (see _readChunk) may carry fewer than `returned`
        // whole records, so advance by what we actually parsed and re-request.
        int parsed = 0;
        for (int i = 0; i < returned; i++) {
          if (r.remaining < FlockYouDetection.wireSize) break;
          out.add(FlockYouDetection.fromReader(r));
          parsed++;
        }
        if (parsed == 0) break;
        idx += parsed;
        if (!hasMore && parsed >= returned) break;
      }
      _flockYouDetections = out;
      _flockYouWithLocation =
          out.where((d) => d.location != null).toList(growable: false);
      _flockYouFetchedAt = DateTime.now();
    } catch (e) {
      _lastError = 'FlockYou fetch failed: $e';
      appLogger.error(_lastError!, tag: _logTag);
    } finally {
      _isLoadingFlockYou = false;
      notifyListeners();
    }
  }

  /// Wipes the on-device detection table (CMD_FLOCKYOU_CLEAR), then clears the
  /// local copy on success.
  Future<bool> clearFlockYouOnDevice() async {
    final ok = await _sendAndAwait(
      Uint8List.fromList([cmdFlockYouClear]),
      respCodeOk,
    );
    if (ok != null) {
      _flockYouDetections = const [];
      _flockYouWithLocation = const [];
      _flockYouFetchedAt = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Drops the locally-cached detections without touching the device.
  void clearFlockYouLocal() {
    if (_flockYouDetections.isEmpty) return;
    _flockYouDetections = const [];
    _flockYouWithLocation = const [];
    _flockYouFetchedAt = null;
    notifyListeners();
  }

  // ── GPS track ───────────────────────────────────────────────────────────

  /// Downloads the full track: pages the chunk index, then pulls each chunk
  /// and decodes its fixes into [gpsTrackFixes] / [gpsTrackPoints].
  Future<void> fetchGpsTrack() async {
    if (_isLoadingGpsTrack) return;
    _isLoadingGpsTrack = true;
    _gpsDownloadProgress = null;
    _lastError = null;
    notifyListeners();
    try {
      final status = await _fetchGpsFullIndex();
      _gpsTrackStatus = status;
      if (status == null) {
        _gpsTrackFixes = const [];
        _gpsTrackPoints = const [];
        return;
      }
      final fixes = <GpsFix>[];
      for (int c = 0; c < status.chunks.length; c++) {
        final chunk = status.chunks[c];
        final bytes = await _readChunk(
          chunk.chunkId,
          chunk.fixCount * GpsFix.wireSize,
        );
        final r = BufferReader(bytes);
        final n = bytes.length ~/ GpsFix.wireSize;
        for (int i = 0; i < n; i++) {
          fixes.add(GpsFix.fromReader(r));
        }
        _gpsDownloadProgress =
            status.chunks.isEmpty ? 1.0 : (c + 1) / status.chunks.length;
        notifyListeners();
      }
      _gpsTrackFixes = fixes;
      _gpsTrackPoints = fixes.map((f) => f.location).toList(growable: false);
      _gpsTrackFetchedAt = DateTime.now();
    } catch (e) {
      _lastError = 'GPS track fetch failed: $e';
      appLogger.error(_lastError!, tag: _logTag);
    } finally {
      _isLoadingGpsTrack = false;
      _gpsDownloadProgress = null;
      notifyListeners();
    }
  }

  /// Pages CMD_GPS_TRACK_LIST until every chunk index is collected.
  Future<GpsTrackStatus?> _fetchGpsFullIndex() async {
    final first = await _fetchGpsListPage(0);
    if (first == null) return null;
    final allChunks = <GpsChunkIndex>[...first.chunks];
    // Guard against a runaway loop if the device never reports enough chunks.
    for (int page = 0;
        allChunks.length < first.totalChunks && page < 4096;
        page++) {
      final next = await _fetchGpsListPage(allChunks.length);
      if (next == null || next.chunks.isEmpty) break;
      allChunks.addAll(next.chunks);
      if (!next.hasMore) break;
    }
    return first.withChunks(allChunks);
  }

  Future<GpsTrackStatus?> _fetchGpsListPage(int offset) async {
    final w = BufferWriter()
      ..writeByte(cmdGpsTrackList)
      ..writeUInt16LE(offset);
    final resp = await _sendAndAwait(w.toBytes(), respCodeGpsTrackList);
    if (resp == null) return null;
    return GpsTrackStatus.parse(resp);
  }

  /// Pulls one chunk fully by paging CMD_GPS_TRACK_DOWNLOAD_CHUNK from offset 0.
  /// Response: [code][u16 got][u8 has_more][data]. `expectedBytes` is the chunk
  /// size from the index (fixCount × 16).
  ///
  /// Note: the transport may deliver fewer data bytes than `got` claims — over
  /// BLE the firmware's page (up to MAX_FRAME_SIZE = 176 B) can exceed the
  /// negotiated ATT MTU and arrive truncated, with no reassembly on the receive
  /// side. So we advance by the bytes *actually present*, not the claimed
  /// count, and re-request from the true offset (the firmware re-seeks per
  /// request). That reads the whole chunk in MTU-sized contiguous slices and is
  /// a no-op over USB/TCP where the frame arrives intact (actual == got).
  Future<Uint8List> _readChunk(int chunkId, int expectedBytes) async {
    final buf = BytesBuilder();
    int offset = 0;
    // Bound the loop generously; at the worst case (~20-byte MTU slices) a large
    // chunk still finishes well under this.
    for (int page = 0; page < 100000; page++) {
      if (expectedBytes > 0 && buf.length >= expectedBytes) break;
      final w = BufferWriter()
        ..writeByte(cmdGpsTrackDownloadChunk)
        ..writeUInt32LE(chunkId)
        ..writeUInt32LE(offset);
      final resp = await _sendAndAwait(w.toBytes(), respCodeGpsTrackChunk);
      if (resp == null || resp.length < 4) break;
      final r = BufferReader(resp);
      r.skipBytes(1); // response code
      final claimed = r.readUInt16LE();
      final hasMore = r.readUInt8() != 0;
      final actual = r.remaining; // bytes truly present (< claimed if truncated)
      if (actual <= 0) break;
      buf.add(r.readBytes(actual));
      offset += actual;
      // When the size is unknown, fall back to the device's has_more, but only
      // trust it once we've received the page it claims to have sent in full.
      if (expectedBytes <= 0 && !hasMore && actual >= claimed) break;
    }
    return buf.toBytes();
  }

  /// Wipes the on-device track ring (CMD_GPS_TRACK_CLEAR), then clears the
  /// local copy on success.
  Future<bool> clearGpsTrackOnDevice() async {
    final ok = await _sendAndAwait(
      Uint8List.fromList([cmdGpsTrackClear]),
      respCodeOk,
    );
    if (ok != null) {
      _gpsTrackFixes = const [];
      _gpsTrackPoints = const [];
      _gpsTrackStatus = null;
      _gpsTrackFetchedAt = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Drops the locally-cached track without touching the device.
  void clearGpsTrackLocal() {
    if (_gpsTrackFixes.isEmpty && _gpsTrackStatus == null) return;
    _gpsTrackFixes = const [];
    _gpsTrackPoints = const [];
    _gpsTrackStatus = null;
    _gpsTrackFetchedAt = null;
    notifyListeners();
  }
}
