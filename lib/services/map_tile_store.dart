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
  static const int _schemaVersion = 2;

  Database? _db;

  /// Row id of the archive tiles are currently read from and written to.
  int _sourceId = 0;
  int get sourceId => _sourceId;

  /// Opens (creating if needed) the store under [directoryPath].
  ///
  /// [sourceUrl] identifies the archive in use. Tiles are scoped to it, so
  /// switching archives cannot serve one schema's tiles under another's style —
  /// which is otherwise silent, since an unmatched source-layer renders as
  /// absence rather than an error.
  Future<void> open(String directoryPath, {String? sourceUrl}) async {
    if (_db != null) {
      if (sourceUrl != null) await useSource(sourceUrl);
      return;
    }
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
      onUpgrade: (db, from, to) async {
        if (from < 2) await _createV2(db, dropLegacyTiles: true);
      },
      onCreate: (db, version) async {
        await _createV2(db, dropLegacyTiles: false);
      },
    );
    if (sourceUrl != null) await useSource(sourceUrl);
  }

  /// Schema v2: tiles scoped to a source, plus the route cache.
  ///
  /// Storage notes — these are all rowid tables. A `WITHOUT ROWID` table stores
  /// whole rows in the primary-key btree, which SQLite recommends only for
  /// small rows; measured on real data our ~17 KB tiles came out 5 MB *larger*
  /// that way, because they spill to overflow pages.
  static Future<void> _createV2(
    Database db, {
    required bool dropLegacyTiles,
  }) async {
    if (dropLegacyTiles) {
      // v1 tiles carry no record of which archive produced them. Attributing
      // them to the current source would be a guess, and a wrong guess
      // reintroduces exactly the schema-mixing this table exists to prevent —
      // so they go. They refetch by browsing.
      await db.execute('DROP TABLE IF EXISTS tiles');
      await db.execute('DROP TABLE IF EXISTS regions');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sources (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        url        TEXT    NOT NULL UNIQUE,
        first_seen INTEGER NOT NULL,
        last_used  INTEGER NOT NULL
      )
    ''');

    // source_id costs about a byte a row; the alternative — one table per
    // archive — trades that for schema churn on every URL change.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tile_data (
        source_id   INTEGER NOT NULL,
        zoom_level  INTEGER NOT NULL,
        tile_column INTEGER NOT NULL,
        tile_row    INTEGER NOT NULL,
        tile_data   BLOB    NOT NULL,
        fetched_at  INTEGER NOT NULL,
        PRIMARY KEY (source_id, zoom_level, tile_column, tile_row)
      )
    ''');

    // Keeps the file readable by MBTiles tools, which expect exactly
    // tiles(zoom_level, tile_column, tile_row, tile_data). The view exposes
    // whichever source is active; writes go to tile_data.
    await db.execute('''
      CREATE VIEW IF NOT EXISTS tiles AS
        SELECT zoom_level, tile_column, tile_row, tile_data
        FROM tile_data
        WHERE source_id = (
          SELECT CAST(value AS INTEGER) FROM metadata WHERE name = 'active_source_id'
        )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS regions (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id  INTEGER NOT NULL DEFAULT 0,
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

    // Cached routing responses, so a route already asked for is redrawn
    // without touching the routing server.
    //
    // Storage: coordinates are integer microdegrees rather than REAL — SQLite
    // stores a 4-byte int where a float always costs 8, and e6 is the same
    // precision the firmware uses. `shape` stays in Valhalla's encoded-polyline
    // form, which is the compact representation; expanding it to coordinate
    // pairs would cost roughly ten times as much. Maneuvers are gzipped JSON.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS routes (
        request_hash BLOB    NOT NULL UNIQUE,
        costing      TEXT    NOT NULL,
        from_lat_e6  INTEGER NOT NULL,
        from_lon_e6  INTEGER NOT NULL,
        to_lat_e6    INTEGER NOT NULL,
        to_lon_e6    INTEGER NOT NULL,
        distance_m   INTEGER NOT NULL,
        duration_s   INTEGER NOT NULL,
        shape        TEXT    NOT NULL,
        maneuvers    BLOB,
        created_at   INTEGER NOT NULL,
        last_used    INTEGER NOT NULL
      )
    ''');

    for (final e in const {
      'name': 'MeshCore Open basemap',
      'format': 'pbf',
      'type': 'baselayer',
    }.entries) {
      await db.insert('metadata', {'name': e.key, 'value': e.value},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Selects (creating if needed) the archive tiles are scoped to.
  Future<void> useSource(String url) async {
    final db = _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('sources', {
      'url': url,
      'first_seen': now,
      'last_used': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final rows = await db.query('sources',
        columns: ['id'], where: 'url = ?', whereArgs: [url], limit: 1);
    _sourceId = rows.first['id'] as int;
    await db.update('sources', {'last_used': now},
        where: 'id = ?', whereArgs: [_sourceId]);
    // Drives the MBTiles-compatibility view.
    await db.insert('metadata',
        {'name': 'active_source_id', 'value': '$_sourceId'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Every archive the store holds tiles for, with per-source totals.
  Future<List<({int id, String url, int tiles, int bytes})>> sources() async {
    final rows = await _database.rawQuery('''
      SELECT s.id, s.url,
             COUNT(t.source_id)                    AS tiles,
             COALESCE(SUM(LENGTH(t.tile_data)), 0) AS bytes
      FROM sources s
      LEFT JOIN tile_data t ON t.source_id = s.id
      GROUP BY s.id, s.url
      ORDER BY s.last_used DESC
    ''');
    return [
      for (final r in rows)
        (
          id: r['id'] as int,
          url: r['url'] as String,
          tiles: (r['tiles'] as num).toInt(),
          bytes: (r['bytes'] as num).toInt(),
        ),
    ];
  }

  /// Drops everything belonging to one archive.
  Future<void> deleteSource(int id) async {
    await _database.transaction((txn) async {
      await txn.delete('tile_data', where: 'source_id = ?', whereArgs: [id]);
      await txn.delete('regions', where: 'source_id = ?', whereArgs: [id]);
      await txn.delete('sources', where: 'id = ?', whereArgs: [id]);
    });
    await _vacuum();
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
      'tile_data',
      columns: ['tile_data'],
      where: 'source_id = ? AND zoom_level = ? AND tile_column = ? '
          'AND tile_row = ?',
      whereArgs: [_sourceId, z, x, _tmsRow(z, y)],
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
      'tile_data',
      columns: ['tile_column', 'tile_row', 'LENGTH(tile_data) AS len'],
      where:
          'source_id = ? AND zoom_level = ? AND tile_column BETWEEN ? AND ? '
          'AND tile_row BETWEEN ? AND ?',
      whereArgs: [
        _sourceId,
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
      'tile_data',
      columns: ['1'],
      where: 'source_id = ? AND zoom_level = ? AND tile_column = ? '
          'AND tile_row = ?',
      whereArgs: [_sourceId, z, x, _tmsRow(z, y)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Writes (or replaces) tile z/x/y. Pass empty [data] to record a tombstone.
  Future<void> putTile(int z, int x, int y, Uint8List data) async {
    await _database.insert('tile_data', {
      'source_id': _sourceId,
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
      batch.insert('tile_data', {
        'source_id': _sourceId,
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
        await _database.rawQuery(
          'SELECT COUNT(*) FROM tile_data WHERE source_id = ?', [_sourceId]),
      ) ??
      0;

  /// Total bytes of tile payloads (excludes SQLite overhead).
  Future<int> totalBytes() async =>
      Sqflite.firstIntValue(
        await _database.rawQuery(
          'SELECT COALESCE(SUM(LENGTH(tile_data)),0) FROM tile_data '
          'WHERE source_id = ?', [_sourceId]),
      ) ??
      0;

  // ── Regions ──────────────────────────────────────────────────────────────

  Future<List<MapRegion>> regions() async {
    final rows = await _database.query('regions',
        where: 'source_id = ?', whereArgs: [_sourceId], orderBy: 'created_at DESC');
    return rows.map(MapRegion.fromRow).toList();
  }

  Future<int> insertRegion(MapRegion region) => _database.insert(
      'regions', region.toRow()..remove('id')..['source_id'] = _sourceId);

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
        await txn.delete('tile_data', where: where.toString(), whereArgs: args);
      }
      await txn.delete('regions', where: 'id = ?', whereArgs: [id]);
    });
    await _vacuum();
  }

  /// Drops every tile and region belonging to the active source.
  ///
  /// Other archives in the store are untouched; use [deleteSource] for those.
  Future<void> clearAll() async {
    await _database.transaction((txn) async {
      await txn.delete(
        'tile_data',
        where: 'source_id = ?',
        whereArgs: [_sourceId],
      );
      await txn.delete(
        'regions',
        where: 'source_id = ?',
        whereArgs: [_sourceId],
      );
    });
    await _vacuum();
  }

  // ── Route cache ──────────────────────────────────────────────────────────

  /// Stores a routing response, keyed by [requestHash] so an identical request
  /// is answered from disk instead of the routing server.
  ///
  /// [maneuvers] should be gzipped JSON — turn-by-turn text compresses well and
  /// is never queried, only replayed.
  Future<void> putRoute({
    required Uint8List requestHash,
    required String costing,
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required int distanceMetres,
    required int durationSeconds,
    required String shape,
    Uint8List? maneuvers,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.insert('routes', {
      'request_hash': requestHash,
      'costing': costing,
      // Microdegrees: a 4-byte int where a REAL always costs 8, at the same
      // precision the firmware's GPS records use.
      'from_lat_e6': (fromLat * 1e6).round(),
      'from_lon_e6': (fromLon * 1e6).round(),
      'to_lat_e6': (toLat * 1e6).round(),
      'to_lon_e6': (toLon * 1e6).round(),
      'distance_m': distanceMetres,
      'duration_s': durationSeconds,
      'shape': shape,
      'maneuvers': maneuvers,
      'created_at': now,
      'last_used': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// A previously stored route, or null. Touches `last_used` so eviction can
  /// favour routes nobody asks for.
  Future<CachedRoute?> getRoute(Uint8List requestHash) async {
    final rows = await _database.query(
      'routes',
      where: 'request_hash = ?',
      whereArgs: [requestHash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    await _database.update(
      'routes',
      {'last_used': DateTime.now().millisecondsSinceEpoch},
      where: 'request_hash = ?',
      whereArgs: [requestHash],
    );
    final r = rows.first;
    final blob = r['maneuvers'];
    return CachedRoute(
      costing: r['costing'] as String,
      fromLat: (r['from_lat_e6'] as int) / 1e6,
      fromLon: (r['from_lon_e6'] as int) / 1e6,
      toLat: (r['to_lat_e6'] as int) / 1e6,
      toLon: (r['to_lon_e6'] as int) / 1e6,
      distanceMetres: r['distance_m'] as int,
      durationSeconds: r['duration_s'] as int,
      shape: r['shape'] as String,
      maneuvers: blob == null
          ? null
          : (blob is Uint8List ? blob : Uint8List.fromList(blob as List<int>)),
    );
  }

  Future<({int count, int bytes})> routeStats() async {
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS c, '
      'COALESCE(SUM(LENGTH(shape) + LENGTH(COALESCE(maneuvers, x\'\'))), 0) AS b '
      'FROM routes',
    );
    return (
      count: (rows.first['c'] as num).toInt(),
      bytes: (rows.first['b'] as num).toInt(),
    );
  }

  Future<void> clearRoutes() async {
    await _database.delete('routes');
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

/// A routing response replayed from the local cache.
class CachedRoute {
  final String costing;
  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;
  final int distanceMetres;
  final int durationSeconds;

  /// Valhalla's encoded polyline (precision 6) — kept encoded because that is
  /// the compact form; expanding it to coordinate pairs costs roughly ten
  /// times as much to store.
  final String shape;

  /// Gzipped turn-by-turn JSON, or null when the caller did not ask for it.
  final Uint8List? maneuvers;

  const CachedRoute({
    required this.costing,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.distanceMetres,
    required this.durationSeconds,
    required this.shape,
    this.maneuvers,
  });
}
