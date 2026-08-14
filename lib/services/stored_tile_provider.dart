import 'dart:io';
import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'map_tile_store.dart';
import 'pmtiles_vector_tile_provider.dart';

/// Basemap tile source: durable local store first, network only to fill gaps.
///
/// Read order for every tile:
///   1. [MapTileStore] — tiles previously browsed or pre-downloaded.
///   2. A locally-downloaded PMTiles archive, when one exists. Tiles served
///      from here are deliberately **not** copied into the store: the bytes are
///      already on disk, so a second copy would be pure duplication.
///   3. The remote archive over HTTP range — the result is written to the store
///      so the same tile is never fetched twice.
///
/// In offline-only mode step 3 is skipped entirely, so the map renders from
/// local data and nothing touches the network.
///
/// Tiles are held **gzip-compressed** — roughly a third the size of decoded
/// MVT. That is an invariant of the store, not of the source: PMTiles archives
/// normally store gzip (ours does), so the bytes pass through untouched, but an
/// uncompressed archive is deflated on the way in. Reads therefore always
/// inflate, with no per-archive negotiation.
class StoredTileProvider extends VectorTileProvider {
  final MapTileStore store;

  /// Fills gaps over the network. Null in offline-only mode.
  final PmTilesVectorTileProvider? remote;

  /// Whole-archive download, when present. Read-only, never written back.
  final PmTilesVectorTileProvider? localArchive;

  @override
  final int minimumZoom;

  @override
  final int maximumZoom;

  StoredTileProvider({
    required this.store,
    required this.remote,
    required this.localArchive,
    required this.minimumZoom,
    required this.maximumZoom,
  });

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    if (tile.z < minimumZoom || tile.z > maximumZoom || !tile.isValid()) {
      throw ProviderException(
        message: 'tile $tile outside archive range '
            '($minimumZoom-$maximumZoom)',
        retryable: Retryable.none,
        statusCode: 400,
      );
    }

    final stored = await store.getTile(tile.z, tile.x, tile.y);
    if (stored != null) {
      // Zero length is a tombstone: the archive has no tile here. Report it as
      // absent rather than refetching it on every pan.
      if (stored.isEmpty) throw _absent(tile);
      return _inflate(stored, tile);
    }

    final archive = localArchive;
    if (archive != null) {
      // Already on disk in the archive — serve it without a second copy.
      return archive.provide(tile);
    }

    final net = remote;
    if (net == null) throw _absent(tile);

    try {
      final gz = await fetchAsGzip(net, tile);
      await store.putTile(tile.z, tile.x, tile.y, gz);
      return _inflate(gz, tile);
    } on ProviderException catch (e) {
      // Remember genuinely-absent tiles so they cost nothing next time.
      if (e.statusCode == 404 || e.statusCode == 204) {
        await store.putTile(tile.z, tile.x, tile.y, Uint8List(0));
      }
      rethrow;
    }
  }

  /// Fetches a tile from [source] as gzip, ready for the store. Archives that
  /// already store gzip (the norm) pass their bytes through untouched.
  ///
  /// Shared with the region downloader, which writes the same rows.
  static Future<Uint8List> fetchAsGzip(
    PmTilesVectorTileProvider source,
    TileIdentity tile,
  ) async {
    if (source.tilesAreGzip) return source.provideCompressed(tile);
    return Uint8List.fromList(gzip.encode(await source.provide(tile)));
  }

  Uint8List _inflate(Uint8List bytes, TileIdentity tile) {
    try {
      return Uint8List.fromList(gzip.decode(bytes));
    } catch (e) {
      throw ProviderException(
        message: 'failed to decompress stored tile $tile: $e',
        retryable: Retryable.none,
        statusCode: 500,
      );
    }
  }

  ProviderException _absent(TileIdentity tile) => ProviderException(
    message: 'tile $tile not available offline',
    retryable: Retryable.none,
    statusCode: 404,
  );

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;

  Future<void> close() async {
    await remote?.close();
    await localArchive?.close();
  }
}
