import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
// Prefixed to avoid TileLayer/Theme name clashes with material/flutter_map.
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'app_settings_service.dart';
import 'pmtiles_vector_tile_provider.dart';

/// Protomaps-v4-schema style matching our PMTiles layers (earth/water/roads/
/// buildings/…). No labels yet (avoids the glyph dependency).
const String _vectorStyleAsset = 'assets/map/protomaps_light.json';

/// Filename of the locally-downloaded PMTiles archive used for offline maps.
const String _offlineFileName = 'offline_basemap.pmtiles';

/// vector_map_tiles' default disk-cache folder (see byte_storage_factory_io.dart:
/// `<temp>/.vector_map`). We don't override cacheFolder — the `Directory`
/// typedef is web-stubbed to `String`, so a dart:io cacheFolder trips analysis;
/// instead we let the package use its default and clear that folder directly.
const String _vectorCacheFolderName = '.vector_map';

/// Runtime disk cache size for decoded/raw vector tiles. Larger than the
/// package default (50 MB) so more of a browsing session survives offline.
const int _vectorCacheMaxBytes = 512 * 1024 * 1024;

/// Vector-only map basemap service.
///
/// Renders a self-hosted Protomaps PMTiles archive as a flutter_map
/// [vmt.VectorTileLayer], read over HTTP range (or from a local file when an
/// offline copy has been downloaded). Two caching layers:
///   1. vector_map_tiles' persistent disk cache (browsed tiles survive
///      restarts and work offline for viewed areas).
///   2. a full-archive offline download — the whole .pmtiles copied locally;
///      the provider then reads the local path for complete offline coverage.
class MapTileCacheService extends ChangeNotifier {
  static const String userAgentPackageName = 'com.meshcore.open';

  final AppSettingsService appSettingsService;

  String _lastUrl;
  bool _lastUseOffline;

  MapTileCacheService({required this.appSettingsService})
    : _lastUrl = appSettingsService.settings.mapVectorTilesUrl,
      _lastUseOffline = appSettingsService.settings.mapVectorUseOffline {
    appSettingsService.addListener(_handleSettingsChanged);
  }

  // ── Directories ────────────────────────────────────────────────
  Directory? _appDir;
  Future<Directory> _appSupport() async =>
      _appDir ??= await getApplicationSupportDirectory();

  Future<File> _offlineFile() async =>
      File('${(await _appSupport()).path}/$_offlineFileName');

  // ── Offline archive management ─────────────────────────────────
  double? _downloadProgress; // 0..1 while downloading, null when idle
  bool get isDownloadingOffline => _downloadProgress != null;
  double? get offlineDownloadProgress => _downloadProgress;

  Future<bool> offlineArchiveExists() async => (await _offlineFile()).exists();

  Future<int> offlineArchiveBytes() async {
    final f = await _offlineFile();
    return (await f.exists()) ? await f.length() : 0;
  }

  /// Streams the configured tiles URL to a local file with progress. The
  /// download writes to a .part file and renames on success so a partial
  /// download never masquerades as a complete archive.
  Future<void> downloadOfflineArchive() async {
    if (isDownloadingOffline) return;
    final url = appSettingsService.settings.mapVectorTilesUrl;
    final target = await _offlineFile();
    final part = File('${target.path}.part');
    final client = http.Client();
    _downloadProgress = 0;
    notifyListeners();
    IOSink? sink;
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(url)));
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode} downloading $url');
      }
      final total = resp.contentLength ?? 0;
      int received = 0;
      sink = part.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _downloadProgress = received / total;
          notifyListeners();
        }
      }
      await sink.close();
      sink = null;
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
      _downloadProgress = null;
      _invalidateVector(); // pick up the new local file if using offline
      notifyListeners();
    }
  }

  Future<void> deleteOfflineArchive() async {
    final f = await _offlineFile();
    if (await f.exists()) await f.delete();
    _invalidateVector();
    notifyListeners();
  }

  /// Clears the runtime vector-tile disk cache (not the offline archive).
  /// Targets vector_map_tiles' default folder under the temp directory.
  Future<void> clearCache() async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/$_vectorCacheFolderName',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
    _invalidateVector();
    notifyListeners();
  }

  // ── Vector resources (memoized, stable future for FutureBuilder) ──
  Future<_VectorResources>? _vectorFuture;

  Future<_VectorResources> _vectorResources() =>
      _vectorFuture ??= _buildVectorResources();

  Future<_VectorResources> _buildVectorResources() async {
    final settings = appSettingsService.settings;
    String source = settings.mapVectorTilesUrl;
    if (settings.mapVectorUseOffline) {
      final f = await _offlineFile();
      if (await f.exists()) source = f.path; // local archive
    }
    final provider = await PmTilesVectorTileProvider.connect(source);
    final styleJson = await rootBundle.loadString(_vectorStyleAsset);
    final theme = vtr.ThemeReader().read(
      jsonDecode(styleJson) as Map<String, dynamic>,
    );
    return _VectorResources(provider: provider, theme: theme);
  }

  void _invalidateVector() {
    final old = _vectorFuture;
    _vectorFuture = null;
    // Close the previous provider's client/handle once it resolves.
    old?.then((r) => r.provider.close()).catchError((_) {});
  }

  void _handleSettingsChanged() {
    final s = appSettingsService.settings;
    if (s.mapVectorTilesUrl != _lastUrl ||
        s.mapVectorUseOffline != _lastUseOffline) {
      _lastUrl = s.mapVectorTilesUrl;
      _lastUseOffline = s.mapVectorUseOffline;
      _invalidateVector();
    }
    notifyListeners();
  }

  Widget buildTileLayer(BuildContext context, {double opacity = 1}) {
    Widget layer = _VectorBasemapLayer(resourcesFuture: _vectorResources());
    if (opacity < 1) layer = Opacity(opacity: opacity, child: layer);
    return layer;
  }

  @override
  void dispose() {
    appSettingsService.removeListener(_handleSettingsChanged);
    _invalidateVector();
    super.dispose();
  }
}

class _VectorResources {
  final PmTilesVectorTileProvider provider;
  final vtr.Theme theme;

  const _VectorResources({required this.provider, required this.theme});
}

/// Renders the vector basemap once its resources (connected provider + parsed
/// theme) are ready. While connecting / on error it renders nothing so the
/// FlutterMap background shows and overlay layers still draw. Self-contained
/// via FutureBuilder because callers use context.read (no rebuild on notify).
class _VectorBasemapLayer extends StatelessWidget {
  final Future<_VectorResources> resourcesFuture;

  const _VectorBasemapLayer({required this.resourcesFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_VectorResources>(
      future: resourcesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final r = snapshot.data!;
          return vmt.VectorTileLayer(
            tileProviders: vmt.TileProviders({'protomaps': r.provider}),
            theme: r.theme,
            fileCacheMaximumSizeInBytes: _vectorCacheMaxBytes,
            fileCacheTtl: const Duration(days: 60),
          );
        }
        if (snapshot.hasError) {
          debugPrint('vector basemap failed: ${snapshot.error}');
        }
        return const SizedBox.shrink();
      },
    );
  }
}
