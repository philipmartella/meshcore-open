import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/map_tile_store.dart';
import 'package:meshcore_open/services/pmtiles_vector_tile_provider.dart';
import 'package:meshcore_open/services/stored_tile_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// End-to-end check of the offline store against the real PMTiles server.
///
/// Skipped automatically when the local tiles stack is not running, so this
/// stays safe in CI; run `docker compose up -d` in srv/tiles-meshcore to
/// exercise it.
const String _tilesUrl = 'http://localhost:8088/tiles/se10-z15.pmtiles';

Future<bool> _serverUp() async {
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    final req = await client.getUrl(Uri.parse(_tilesUrl));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-15');
    final resp = await req.close();
    await resp.drain<void>();
    client.close();
    return resp.statusCode == 206 || resp.statusCode == 200;
  } catch (_) {
    return false;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fetches a tile once, then serves it from the store offline', () async {
    if (!await _serverUp()) {
      markTestSkipped('tiles-meshcore server not reachable at $_tilesUrl');
      return;
    }

    final tmp = await Directory.systemTemp.createTemp('stored_provider_test');
    final store = MapTileStore();
    await store.open(tmp.path);
    final remote = await PmTilesVectorTileProvider.connect(_tilesUrl);

    // Somewhere well inside the archive's bbox (northern Georgia).
    final tile = TileIdentity(10, 266, 406);

    try {
      final online = StoredTileProvider(
        store: store,
        remote: remote,
        localArchive: null,
        minimumZoom: remote.minimumZoom,
        maximumZoom: remote.maximumZoom,
      );

      final first = await online.provide(tile);
      expect(first, isNotEmpty, reason: 'expected decoded MVT bytes');
      expect(await store.tileCount(), 1, reason: 'fetch must populate store');

      // Stored bytes are gzip, so they should be materially smaller than the
      // decoded tile the renderer receives.
      final storedBytes = await store.totalBytes();
      expect(storedBytes, lessThan(first.length));

      // Now prove the store alone can serve it: no remote, no archive.
      final offline = StoredTileProvider(
        store: store,
        remote: null,
        localArchive: null,
        minimumZoom: remote.minimumZoom,
        maximumZoom: remote.maximumZoom,
      );
      final second = await offline.provide(tile);
      expect(second, equals(first), reason: 'offline read must match');

      // A tile that was never fetched must fail cleanly offline rather than
      // hanging or returning garbage.
      await expectLater(
        offline.provide(TileIdentity(10, 267, 406)),
        throwsA(isA<ProviderException>()),
      );
    } finally {
      await remote.close();
      await store.close();
      await tmp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
