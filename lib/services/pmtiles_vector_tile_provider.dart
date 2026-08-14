import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Bridges a PMTiles archive (read over HTTP range via the `pmtiles` package)
/// to vector_map_tiles' [VectorTileProvider].
///
/// This is our own glue in place of the `vector_map_tiles_pmtiles` package,
/// which is unmaintained and pinned to flutter_map 7. Open an archive with
/// [connect]; the archive header supplies min/max zoom and tile type, and
/// [provide] returns decompressed MVT bytes for the renderer.
///
/// The archive may be local (`/path/to.pmtiles`) or remote
/// (`https://host/x.pmtiles`) — remote archives are read incrementally with
/// HTTP range requests, never fully downloaded.
///
/// NOTE (web): pmtiles 1.2.0 decompresses tiles with `dart:io`'s zlib, so
/// [provide] works on mobile and desktop but not Flutter web. Web support
/// would need decoding [Tile.compressedBytes] with a pure-Dart gzip decoder.
/// Web BLE is unavailable anyway, so this is not a regression for that target.
class PmTilesVectorTileProvider extends VectorTileProvider {
  final PmTilesArchive _archive;

  @override
  final int minimumZoom;

  @override
  final int maximumZoom;

  PmTilesVectorTileProvider._(
    this._archive,
    this.minimumZoom,
    this.maximumZoom,
  );

  /// Opens a PMTiles archive from a local path or an http(s) URL and returns a
  /// provider scoped to the archive's own zoom range. Throws [ArgumentError]
  /// if the archive does not hold vector (MVT) tiles.
  static Future<PmTilesVectorTileProvider> connect(String pathOrUrl) async {
    final archive = await PmTilesArchive.from(pathOrUrl);
    if (archive.tileType != TileType.mvt) {
      await archive.close();
      throw ArgumentError(
        'PMTiles tile type is ${archive.tileType}, expected mvt',
      );
    }
    return PmTilesVectorTileProvider._(
      archive,
      archive.minZoom,
      archive.maxZoom,
    );
  }

  /// True when the archive stores its tiles gzip-compressed (the norm, and
  /// what our Protomaps builds use). Lets callers keep the compressed bytes
  /// rather than paying to inflate and re-deflate them.
  bool get tilesAreGzip => _archive.tileCompression == Compression.gzip;

  /// The tile's bytes exactly as stored in the archive, still compressed.
  /// Same lookup and error contract as [provide].
  Future<Uint8List> provideCompressed(TileIdentity tile) =>
      _read(tile, (t) => t.compressedBytes());

  @override
  Future<Uint8List> provide(TileIdentity tile) => _read(tile, (t) => t.bytes());

  Future<Uint8List> _read(
    TileIdentity tile,
    List<int> Function(Tile) extract,
  ) async {
    if (tile.z < minimumZoom || tile.z > maximumZoom || !tile.isValid()) {
      throw ProviderException(
        message: 'tile $tile outside archive range '
            '($minimumZoom-$maximumZoom)',
        retryable: Retryable.none,
        statusCode: 400,
      );
    }
    // PMTiles addresses tiles by a Hilbert-curve id derived from z/x/y using
    // the same XYZ (top-left origin) convention flutter_map uses — no Y flip.
    final tileId = ZXY(tile.z, tile.x, tile.y).toTileId();
    try {
      final t = await _archive.tile(tileId);
      return Uint8List.fromList(extract(t));
    } on TileNotFoundException {
      // The archive deduped/omitted this cell (e.g. genuinely empty). A
      // non-retryable ProviderException tells vector_map_tiles to render
      // nothing here rather than retry.
      throw ProviderException(
        message: 'tile $tile not present in archive',
        retryable: Retryable.none,
        statusCode: 404,
      );
    } catch (e) {
      throw ProviderException(
        message: 'PMTiles read failed for $tile: $e',
        retryable: Retryable.retry,
      );
    }
  }

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;

  /// Releases the underlying archive's HTTP client / file handle.
  Future<void> close() => _archive.close();
}
