import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
// Prefixed to avoid TileLayer/Theme name clashes with material/flutter_map.
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../models/map_region.dart';
import '../utils/app_logger.dart';
import 'app_settings_service.dart';
import 'map_region_downloader.dart';
import 'map_tile_store.dart';
import 'pmtiles_vector_tile_provider.dart';
import 'stored_tile_provider.dart';

/// OpenMapTiles-schema styles matching what tilemaker produces from the OSM
/// extract (ocean/water/transportation/building/…). No labels yet (avoids the
/// glyph dependency). Same layer structure in both — only the colors differ, so
/// the tiles are identical and switching themes never refetches.
///
/// Note there is no `earth` layer in this schema as there was in Protomaps v4:
/// land is the background color, and sea is painted over it from `ocean`, which
/// tilemaker derives from a coastline shapefile rather than from OSM.
///
/// Each file declares a distinct `"id"`: vector_tile_renderer keys its render
/// cache on it (defaulting to `default`), so identical ids would serve
/// light-styled tiles in dark mode.
const String _vectorStyleLightAsset = 'assets/map/omt_light.json';
const String _vectorStyleDarkAsset = 'assets/map/omt_dark.json';

/// Source name the styles declare, and therefore the key the provider must be
/// registered under. These have to agree: a mismatch renders an empty map with
/// no error, because every layer references a source that does not exist.
const String _vectorSourceName = 'openmaptiles';

/// Filename of an optional whole-archive download — the shortcut for "give me
/// the entire region" instead of pre-downloading area by area.
const String _offlineFileName = 'offline_basemap.pmtiles';

/// vector_map_tiles' own disk cache folder (`<temp>/.vector_map`).
const String _renderCacheFolderName = '.vector_map';

/// Size cap for that render cache.
///
/// It holds *decoded* tiles and sits above our provider, so it cannot be turned
/// off through the package API (its `put` always writes, trimming only every
/// 20th call). Keeping it small makes it a cheap hot-tile buffer instead of a
/// second, competing copy of the basemap — the durable copy is [MapTileStore].
const int _renderCacheMaxBytes = 32 * 1024 * 1024;

/// Basemap service: a durable local tile store, filled on demand and by
/// explicit region downloads.
///
/// Every tile the map renders is read through [MapTileStore]; a miss is fetched
/// from the remote PMTiles archive and written there, so browsing builds
/// offline coverage as a side effect. [downloadRegion] pre-fills an area
/// through the same path. Nothing expires — tiles leave only when the user
/// deletes a region or clears the store.
class MapTileCacheService extends ChangeNotifier {
  static const String userAgentPackageName = 'com.meshcore.open';

  final AppSettingsService appSettingsService;
  final MapTileStore store = MapTileStore();
  late final MapRegionDownloader _downloader = MapRegionDownloader(store);

  String _lastUrl;
  bool _lastOfflineOnly;

  MapTileCacheService({required this.appSettingsService})
    : _lastUrl = appSettingsService.settings.mapVectorTilesUrl,
      _lastOfflineOnly = appSettingsService.settings.mapOfflineOnly {
    appSettingsService.addListener(_handleSettingsChanged);
  }

  // ── Storage ────────────────────────────────────────────────────
  Directory? _appDir;
  Future<Directory> _appSupport() async =>
      _appDir ??= await getApplicationSupportDirectory();

  Future<File> _offlineFile() async =>
      File('${(await _appSupport()).path}/$_offlineFileName');

  Future<void> _ensureStoreOpen() async {
    // Passing the archive URL scopes every read and write to that source, so
    // switching archives cannot serve one schema's tiles under another's
    // style — a failure that renders as a blank map rather than an error.
    await store.open(
      (await _appSupport()).path,
      sourceUrl: appSettingsService.settings.mapVectorTilesUrl,
    );
  }

  /// Tiles held locally (including tombstones for empty cells).
  Future<int> storedTileCount() async {
    await _ensureStoreOpen();
    return store.tileCount();
  }

  /// Bytes of stored tile payloads.
  Future<int> storedBytes() async {
    await _ensureStoreOpen();
    return store.totalBytes();
  }

  Future<List<MapRegion>> regions() async {
    await _ensureStoreOpen();
    return store.regions();
  }

  // ── Region downloads ───────────────────────────────────────────
  RegionDownloadProgress? _regionProgress;
  String? _downloadingRegionName;

  bool get isDownloadingRegion => _regionProgress != null;
  RegionDownloadProgress? get regionProgress => _regionProgress;
  String? get downloadingRegionName => _downloadingRegionName;

  /// Deepest zoom the basemap actually carries.
  ///
  /// Offering more in the UI would inflate the pre-download estimate with tiles
  /// the archive cannot supply and the downloader correctly skips.
  Future<int> maxAvailableZoom() async {
    final resources = await _vectorResources();
    return resources.provider.maximumZoom;
  }

  /// Estimated bytes per stored tile, measured from what is already held so the
  /// pre-download estimate reflects this archive's real tile density rather
  /// than a guess. Falls back to a mid-range value on an empty store.
  Future<double> averageTileBytes() async {
    await _ensureStoreOpen();
    final count = await store.tileCount();
    if (count < 50) return 12 * 1024;
    return (await store.totalBytes()) / count;
  }

  /// Downloads [bounds] across an inclusive zoom range into the store.
  ///
  /// Requires network: an offline-only session has no source to read from.
  Future<void> downloadRegion({
    required String name,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) async {
    final region = MapRegion.fromBounds(
      name: name,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    await _ensureStoreOpen();
    await _runDownload(region, await store.insertRegion(region));
  }

  /// Finishes a region whose download was cancelled or interrupted.
  ///
  /// Reuses the existing row rather than adding a second one, and the tiles
  /// already stored are skipped, so this picks up where it stopped.
  Future<void> resumeRegion(MapRegion region) async {
    final id = region.id;
    if (id == null) return;
    await _ensureStoreOpen();
    await _runDownload(region, id);
  }

  Future<void> _runDownload(MapRegion region, int id) async {
    if (isDownloadingRegion) return;

    final resources = await _vectorResources();
    final source = resources.provider.remote ?? resources.provider.localArchive;
    if (source == null) {
      throw StateError('No tile source available — offline-only with no archive');
    }

    final name = region.name;
    _downloadingRegionName = name;
    _regionProgress = RegionDownloadProgress(
      completed: 0,
      total: region.totalTiles,
      bytes: 0,
      absent: 0,
      failed: 0,
    );
    notifyListeners();

    try {
      await _downloader.download(
        region: region,
        regionId: id,
        source: source,
        onProgress: (p) {
          _regionProgress = p;
          notifyListeners();
        },
      );
    } catch (e) {
      appLogger.error('region download failed: $e', tag: 'MapTileCacheService');
      rethrow;
    } finally {
      _regionProgress = null;
      _downloadingRegionName = null;
      notifyListeners();
    }
  }

  void cancelRegionDownload() => _downloader.cancel();

  /// What long-running store maintenance is in flight, if any.
  ///
  /// Deleting a large area rewrites and vacuums a multi-gigabyte database, so
  /// the UI needs something to show rather than appearing hung.
  String? _busyLabel;
  bool get isBusy => _busyLabel != null;
  String? get busyLabel => _busyLabel;

  Future<T> _withBusy<T>(String label, Future<T> Function() action) async {
    _busyLabel = label;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busyLabel = null;
      notifyListeners();
    }
  }

  Future<void> deleteRegion(int id) async {
    await _ensureStoreOpen();
    await _withBusy('Deleting area…', () => store.deleteRegion(id));
  }

  /// Drops every stored tile and region. The offline archive is untouched.
  Future<void> clearStore() async {
    await _ensureStoreOpen();
    await _withBusy('Clearing map data…', () async {
      await store.clearAll();
      await _clearRenderCache();
    });
  }

  /// Clears vector_map_tiles' ephemeral decoded-tile cache.
  Future<void> _clearRenderCache() async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/$_renderCacheFolderName',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  // ── Whole-archive download ─────────────────────────────────────
  double? _downloadProgress; // 0..1 while downloading, null when idle
  bool get isDownloadingOffline => _downloadProgress != null;
  double? get offlineDownloadProgress => _downloadProgress;

  Future<bool> offlineArchiveExists() async => (await _offlineFile()).exists();

  Future<int> offlineArchiveBytes() async {
    final f = await _offlineFile();
    return (await f.exists()) ? await f.length() : 0;
  }

  /// Streams the whole configured archive to a local file. Bulk alternative to
  /// region downloads for "I want the entire coverage area"; served read-only
  /// and never copied into the store.
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
      _invalidateVector();
      notifyListeners();
    }
  }

  Future<void> deleteOfflineArchive() async {
    final f = await _offlineFile();
    if (await f.exists()) await f.delete();
    _invalidateVector();
    notifyListeners();
  }

  // ── Vector resources (memoized, stable future for FutureBuilder) ──
  Future<_VectorResources>? _vectorFuture;

  Future<_VectorResources> _vectorResources() =>
      _vectorFuture ??= _buildVectorResources();

  Future<_VectorResources> _buildVectorResources() async {
    await _ensureStoreOpen();
    final settings = appSettingsService.settings;

    // A downloaded archive is read directly (no point copying it into the
    // store); the network fills anything neither source has.
    PmTilesVectorTileProvider? localArchive;
    final f = await _offlineFile();
    if (await f.exists()) {
      try {
        localArchive = await PmTilesVectorTileProvider.connect(f.path);
      } catch (e) {
        appLogger.error(
          'offline archive unreadable, ignoring: $e',
          tag: 'MapTileCacheService',
        );
      }
    }

    PmTilesVectorTileProvider? remote;
    if (!settings.mapOfflineOnly) {
      try {
        remote = await PmTilesVectorTileProvider.connect(
          settings.mapVectorTilesUrl,
        );
      } catch (e) {
        // Unreachable server must not blank the map — stored tiles still draw.
        appLogger.error(
          'remote archive unreachable, using local tiles only: $e',
          tag: 'MapTileCacheService',
        );
      }
    }

    // Zoom range comes from whichever archive we can see; with neither (fully
    // offline, no archive) fall back to the standard slippy range so stored
    // tiles still render.
    final reference = remote ?? localArchive;
    final provider = StoredTileProvider(
      store: store,
      remote: remote,
      localArchive: localArchive,
      minimumZoom: reference?.minimumZoom ?? 0,
      maximumZoom: reference?.maximumZoom ?? 15,
    );

    // Both styles are parsed once and held together: they describe the same
    // tiles, so picking one at paint time costs nothing, whereas rebuilding
    // these resources on a theme switch would reconnect the archive.
    final reader = vtr.ThemeReader();
    final lightTheme = reader.read(
      jsonDecode(await rootBundle.loadString(_vectorStyleLightAsset))
          as Map<String, dynamic>,
    );
    final darkTheme = reader.read(
      jsonDecode(await rootBundle.loadString(_vectorStyleDarkAsset))
          as Map<String, dynamic>,
    );
    return _VectorResources(
      provider: provider,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
    );
  }

  void _invalidateVector() {
    final old = _vectorFuture;
    _vectorFuture = null;
    old?.then((r) => r.provider.close()).catchError((_) {});
  }

  void _handleSettingsChanged() {
    final s = appSettingsService.settings;
    if (s.mapVectorTilesUrl != _lastUrl ||
        s.mapOfflineOnly != _lastOfflineOnly) {
      final urlChanged = s.mapVectorTilesUrl != _lastUrl;
      _lastUrl = s.mapVectorTilesUrl;
      _lastOfflineOnly = s.mapOfflineOnly;
      _invalidateVector();
      // Point the store at the new archive so its tiles are kept apart from
      // the previous one's.
      if (urlChanged && store.isOpen) {
        unawaited(store.useSource(s.mapVectorTilesUrl));
      }
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
    unawaited(store.close());
    super.dispose();
  }
}

class _VectorResources {
  final StoredTileProvider provider;
  final vtr.Theme lightTheme;
  final vtr.Theme darkTheme;

  const _VectorResources({
    required this.provider,
    required this.lightTheme,
    required this.darkTheme,
  });

  vtr.Theme themeFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkTheme : lightTheme;
}

/// Renders the vector basemap once its resources (provider chain + parsed
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
            // Keyed by brightness so a theme switch rebuilds the layer with the
            // matching style rather than repainting the old one.
            key: ValueKey(Theme.of(context).brightness),
            tileProviders: vmt.TileProviders({_vectorSourceName: r.provider}),
            theme: r.themeFor(Theme.of(context).brightness),
            fileCacheMaximumSizeInBytes: _renderCacheMaxBytes,
            fileCacheTtl: const Duration(days: 7),
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
