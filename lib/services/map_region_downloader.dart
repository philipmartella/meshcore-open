import 'dart:async';
import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart'
    show ProviderException, TileIdentity;

import '../models/map_region.dart';
import '../utils/app_logger.dart';
import 'map_tile_store.dart';
import 'pmtiles_vector_tile_provider.dart';
import 'stored_tile_provider.dart';

/// Progress of an in-flight region download.
class RegionDownloadProgress {
  final int completed;
  final int total;
  final int bytes;

  /// Tiles the archive had nothing for (ocean, empty cells). Stored as
  /// tombstones and counted as done — they are not failures.
  final int absent;
  final int failed;

  const RegionDownloadProgress({
    required this.completed,
    required this.total,
    required this.bytes,
    required this.absent,
    required this.failed,
  });

  double get fraction => total == 0 ? 1 : (completed / total).clamp(0.0, 1.0);
}

/// Pre-downloads a rectangular area of the basemap into [MapTileStore].
///
/// Tiles are fetched with bounded concurrency straight from the remote PMTiles
/// archive and written through the same gzip invariant the live read path uses,
/// so a pre-downloaded tile and a browsed one are indistinguishable — and the
/// region simply renders from the store afterwards.
///
/// Already-stored tiles are skipped, which makes a download **resumable**: rerun
/// it after a cancel or a crash and it picks up where it stopped.
class MapRegionDownloader {
  /// Concurrent range requests. Enough to saturate a typical link without
  /// burying the tile server in parallel reads of one archive.
  static const int _concurrency = 12;

  /// Tiles buffered before a batch insert. Keeps transactions short so a cancel
  /// stays responsive and progress stays honest.
  static const int _batchSize = 64;

  final MapTileStore store;

  MapRegionDownloader(this.store);

  bool _cancelled = false;

  /// Asks the in-flight download to stop. Tiles already written are kept.
  void cancel() => _cancelled = true;

  /// Downloads every tile in [region] from [source].
  ///
  /// [regionId] is the row updated with running totals. Progress is reported
  /// through [onProgress] as tiles land.
  Future<RegionDownloadProgress> download({
    required MapRegion region,
    required int regionId,
    required PmTilesVectorTileProvider source,
    void Function(RegionDownloadProgress)? onProgress,
  }) async {
    _cancelled = false;

    final queue = <({int z, int x, int y})>[];
    for (int z = region.minZoom; z <= region.maxZoom; z++) {
      // Beyond the archive's own max zoom there is nothing to fetch.
      if (z > source.maximumZoom || z < source.minimumZoom) continue;
      queue.addAll(region.tileRangeForZoom(z).tiles());
    }

    final total = queue.length;
    int completed = 0;
    int bytes = 0;
    int absent = 0;
    int failed = 0;
    int next = 0;
    final pending = <({int z, int x, int y, Uint8List data})>[];

    RegionDownloadProgress snapshot() => RegionDownloadProgress(
      completed: completed,
      total: total,
      bytes: bytes,
      absent: absent,
      failed: failed,
    );

    Future<void> flush() async {
      if (pending.isEmpty) return;
      final batch = List.of(pending);
      pending.clear();
      await store.putTiles(batch);
      await store.updateRegionProgress(
        regionId,
        tileCount: completed,
        bytes: bytes,
        complete: false,
      );
    }

    // Each worker pulls from the shared queue so a slow tile never stalls a
    // fixed slice of the work.
    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;
        final i = next++;
        if (i >= queue.length) return;
        final t = queue[i];

        if (await store.hasTile(t.z, t.x, t.y)) {
          completed++;
          onProgress?.call(snapshot());
          continue;
        }

        try {
          final gz = await StoredTileProvider.fetchAsGzip(
            source,
            TileIdentity(t.z, t.x, t.y),
          );
          pending.add((z: t.z, x: t.x, y: t.y, data: gz));
          bytes += gz.length;
        } on ProviderException catch (e) {
          if (e.statusCode == 404 || e.statusCode == 204) {
            // Genuinely empty cell — tombstone it so it is never refetched.
            pending.add((z: t.z, x: t.x, y: t.y, data: Uint8List(0)));
            absent++;
          } else {
            failed++;
          }
        } catch (e) {
          failed++;
          appLogger.error(
            'region tile ${t.z}/${t.x}/${t.y} failed: $e',
            tag: 'MapRegionDownloader',
          );
        }

        completed++;
        onProgress?.call(snapshot());
        if (pending.length >= _batchSize) await flush();
      }
    }

    await Future.wait(List.generate(_concurrency, (_) => worker()));
    await flush();

    // Complete only when the whole queue landed without failures; a cancelled
    // or partial run stays resumable.
    final complete = !_cancelled && completed >= total && failed == 0;
    await store.updateRegionProgress(
      regionId,
      tileCount: completed,
      bytes: bytes,
      complete: complete,
    );
    return snapshot();
  }
}
