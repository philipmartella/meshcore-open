import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../models/map_region.dart';

/// Durable on-disk basemap tile store — the offline map.
///
/// Every basemap tile the app renders is read through this store. A tile that
/// is missing gets fetched from the remote PMTiles archive and written here, so
/// simply browsing the map builds up offline coverage; region pre-downloads
/// write to the same table through the same path. Nothing is evicted by age or
/// size — deletion is always an explicit user action (delete a region, or clear
/// all). That is the difference between this and the ephemeral render cache
/// `vector_map_tiles` keeps in the temp directory.
///
/// **Schema** is MBTiles-compatible (`tiles(zoom_level, tile_column, tile_row,
/// tile_data)`), so the file opens in standard tools. MBTiles numbers rows from
/// the south (TMS) while flutter_map/PMTiles use XYZ (north-first); the flip
/// lives solely in [_tmsRow] and is applied symmetrically on read and write, so
/// callers only ever deal in XYZ.
///
/// Tile bytes are stored **gzip-compressed** exactly as they come out of the
/// PMTiles archive (~3x smaller than decoded MVT); the provider decompresses on
/// read.
class MapTileStore {
  static const String _dbFileName = 'basemap_tiles.mbtiles';
  static const int _schemaVersion = 1;

  Database? _db;

  /// Opens (creating if needed) the store under [directoryPath].
  Future<void> open(String directoryPath) async {
    if (_db != null) return;
    _db = await openDatabase(
      '$directoryPath/$_dbFileName',
      version: _schemaVersion,
      onConfigure: (db) async {
        // Write-ahead logging so readers never block the writer. Region
        // downloads write in sustained bursts while the UI (and anything else
        // holding the file open) reads totals; under the default rollback
        // journal a reader's SHARED lock stops the writer taking EXCLUSIVE and
        // the download dies with "database is locked".
        await db.rawQuery('PRAGMA journal_mode=WAL');
        // Wait out a transient lock rather than failing the download outright.
        await db.execute('PRAGMA busy_timeout=30000');
        // Safe under WAL — a crash can cost the last commits, which for a
        // resumable tile download simply means refetching a few tiles.
        await db.execute('PRAGMA synchronous=NORMAL');
      },
      onCreate: (db, version) async {
        // MBTiles core.
        await db.execute('''
          CREATE TABLE tiles (
            zoom_level  INTEGER NOT NULL,
            tile_column INTEGER NOT NULL,
            tile_row    INTEGER NOT NULL,
            tile_data   BLOB    NOT NULL,
            fetched_at  INTEGER NOT NULL,
            PRIMARY KEY (zoom_level, tile_column, tile_row)
          )
        ''');
        await db.execute('''
          CREATE TABLE metadata (name TEXT PRIMARY KEY, value TEXT)
        ''');
        // Our own bookkeeping for pre-downloaded areas.
        await db.execute('''
          CREATE TABLE regions (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT    NOT NULL,
            west       REAL    NOT NULL,
            south      REAL    NOT NULL,
            east       REAL    NOT NULL,
            north      REAL    NOT NULL,
            min_zoom   INTEGER NOT NULL,
            max_zoom   INTEGER NOT NULL,
            tile_count INTEGER NOT NULL DEFAULT 0,
            bytes      INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            complete   INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.insert('metadata', {'name': 'name', 'value': 'MeshCore Open basemap'});
        await db.insert('metadata', {'name': 'format', 'value': 'pbf'});
        await db.insert('metadata', {'name': 'type', 'value': 'baselayer'});
      },
    );
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('MapTileStore.open() must be called before use');
    }
    return db;
  }

  bool get isOpen => _db != null;

  /// The journal mode actually in force. Exposed so the WAL configuration can
  /// be asserted rather than assumed.
  Future<String> rawJournalMode() async {
    final rows = await _database.rawQuery('PRAGMA journal_mode');
    return rows.first.values.first.toString();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// XYZ row index -> MBTiles (TMS) row index. Self-inverse for a given zoom.
  static int _tmsRow(int z, int y) => (1 << z) - 1 - y;

  /// Stored bytes for tile z/x/y (XYZ), or null when not stored.
  ///
  /// A zero-length result is a **tombstone**: the archive genuinely has no tile
  /// there (ocean, deduped-empty cell). Callers should treat it as "absent, do
  /// not refetch" rather than as data.
  Future<Uint8List?> getTile(int z, int x, int y) async {
    final rows = await _database.query(
      'tiles',
      columns: ['tile_data'],
      where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
      whereArgs: [z, x, _tmsRow(z, y)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final data = rows.first['tile_data'];
    return data is Uint8List ? data : Uint8List.fromList(data as List<int>);
  }

  /// Packs an XYZ tile into a single int key. Valid while `x`,`y` < 2^z and
  /// z <= 22, which covers every zoom the basemap serves.
  static int tileKey(int z, int x, int y) => x * (1 << z) + y;

  /// Keys and total size of every tile already stored inside [range], in one
  /// query.
  ///
  /// The download path uses this instead of a per-tile [hasTile]: a region can
  /// hold tens of thousands of tiles, and one round-trip each both dominates
  /// the runtime and keeps the database busy enough to starve the writer. The
  /// byte total lets a resumed download report the region's real size rather
  /// than only what the final run happened to fetch.
  Future<({Set<int> keys, int bytes})> storedTilesInRange(
    TileRange range,
  ) async {
    final rows = await _database.query(
      'tiles',
      columns: ['tile_column', 'tile_row', 'LENGTH(tile_data) AS len'],
      where:
          'zoom_level = ? AND tile_column BETWEEN ? AND ? '
          'AND tile_row BETWEEN ? AND ?',
      whereArgs: [
        range.z,
        range.minX,
        range.maxX,
        // TMS inverts the Y order, so the north edge is the larger row index.
        _tmsRow(range.z, range.maxY),
        _tmsRow(range.z, range.minY),
      ],
    );
    return (
      keys: {
        for (final r in rows)
          tileKey(
            range.z,
            r['tile_column'] as int,
            // Back to XYZ — _tmsRow is its own inverse at a given zoom.
            _tmsRow(range.z, r['tile_row'] as int),
          ),
      },
      bytes: rows.fold<int>(0, (sum, r) => sum + ((r['len'] as int?) ?? 0)),
    );
  }

  Future<bool> hasTile(int z, int x, int y) async {
    final rows = await _database.query(
      'tiles',
      columns: ['1'],
      where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
      whereArgs: [z, x, _tmsRow(z, y)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Writes (or replaces) tile z/x/y. Pass empty [data] to record a tombstone.
  Future<void> putTile(int z, int x, int y, Uint8List data) async {
    await _database.insert('tiles', {
      'zoom_level': z,
      'tile_column': x,
      'tile_row': _tmsRow(z, y),
      'tile_data': data,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Batch variant — one transaction for a page of downloaded tiles.
  Future<void> putTiles(Iterable<({int z, int x, int y, Uint8List data})> tiles)
  async {
    final batch = _database.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final t in tiles) {
      batch.insert('tiles', {
        'zoom_level': t.z,
        'tile_column': t.x,
        'tile_row': _tmsRow(t.z, t.y),
        'tile_data': t.data,
        'fetched_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Total stored tiles, including tombstones.
  Future<int> tileCount() async =>
      Sqflite.firstIntValue(
        await _database.rawQuery('SELECT COUNT(*) FROM tiles'),
      ) ??
      0;

  /// Total bytes of tile payloads (excludes SQLite overhead).
  Future<int> totalBytes() async =>
      Sqflite.firstIntValue(
        await _database.rawQuery('SELECT COALESCE(SUM(LENGTH(tile_data)),0) FROM tiles'),
      ) ??
      0;

  // ── Regions ──────────────────────────────────────────────────────────────

  Future<List<MapRegion>> regions() async {
    final rows = await _database.query('regions', orderBy: 'created_at DESC');
    return rows.map(MapRegion.fromRow).toList();
  }

  Future<int> insertRegion(MapRegion region) =>
      _database.insert('regions', region.toRow()..remove('id'));

  Future<void> updateRegionProgress(
    int id, {
    required int tileCount,
    required int bytes,
    required bool complete,
  }) async {
    await _database.update(
      'regions',
      {'tile_count': tileCount, 'bytes': bytes, 'complete': complete ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a region and the tiles it covers.
  ///
  /// Tiles inside another surviving region's box are kept, so overlapping
  /// downloads don't punch holes in each other. Note that on-demand tiles
  /// picked up by browsing inside this box are removed too — they are
  /// indistinguishable from downloaded ones, and "delete this area" is the
  /// behaviour the user asked for.
  Future<void> deleteRegion(int id) async {
    final all = await regions();
    final target = all.where((r) => r.id == id).firstOrNull;
    if (target == null) return;
    final survivors = all.where((r) => r.id != id).toList();

    await _database.transaction((txn) async {
      for (int z = target.minZoom; z <= target.maxZoom; z++) {
        final range = target.tileRangeForZoom(z);
        // Rows are TMS, so the north edge (min Y) becomes the max row.
        final minRow = _tmsRow(z, range.maxY);
        final maxRow = _tmsRow(z, range.minY);

        // Only survivors whose rectangle actually intersects this one can
        // protect any tiles; the rest would just bloat the statement.
        final protecting = survivors
            .where((r) => z >= r.minZoom && z <= r.maxZoom)
            .map((r) => r.tileRangeForZoom(z))
            .where(
              (o) =>
                  o.minX <= range.maxX &&
                  o.maxX >= range.minX &&
                  o.minY <= range.maxY &&
                  o.maxY >= range.minY,
            );

        // One statement per zoom, whatever the tile count. Deleting row by row
        // instead means tens of thousands of round-trips for a large region.
        final where = StringBuffer(
          'zoom_level = ? AND tile_column BETWEEN ? AND ? '
          'AND tile_row BETWEEN ? AND ?',
        );
        final args = <Object?>[z, range.minX, range.maxX, minRow, maxRow];
        for (final o in protecting) {
          where.write(
            ' AND NOT (tile_column BETWEEN ? AND ? AND tile_row BETWEEN ? AND ?)',
          );
          args.addAll([o.minX, o.maxX, _tmsRow(z, o.maxY), _tmsRow(z, o.minY)]);
        }
        await txn.delete('tiles', where: where.toString(), whereArgs: args);
      }
      await txn.delete('regions', where: 'id = ?', whereArgs: [id]);
    });
    await _vacuum();
  }

  /// Drops every tile and region.
  Future<void> clearAll() async {
    await _database.transaction((txn) async {
      await txn.delete('tiles');
      await txn.delete('regions');
    });
    await _vacuum();
  }

  /// Reclaims freed pages so the on-disk size reflects what the UI reports.
  Future<void> _vacuum() async {
    try {
      await _database.execute('VACUUM');
    } catch (_) {
      // Not fatal — the space is reused on subsequent writes regardless.
    }
  }
}
