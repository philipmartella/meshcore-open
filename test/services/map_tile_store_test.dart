import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/models/map_region.dart';
import 'package:meshcore_open/services/map_tile_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The store writes MBTiles (TMS, south-first) rows while every caller speaks
/// XYZ (north-first). A sign error there renders vertically mirrored tiles that
/// still *look* like map data, so it is worth pinning down directly.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('MapTileStore', () {
    late Directory tmp;
    late MapTileStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('tile_store_test');
      store = MapTileStore();
      await store.open(tmp.path, sourceUrl: 'https://a.example/a.pmtiles');
    });

    tearDown(() async {
      await store.close();
      await tmp.delete(recursive: true);
    });

    test('tiles from different archives never mix', () async {
      // The bug this prevents: switching tile URLs left the store serving the
      // previous archive's tiles under the new style. Layer names differ
      // between schemas, so they render as nothing — silently.
      await store.putTile(10, 5, 5, Uint8List.fromList([1, 1, 1]));
      expect(await store.getTile(10, 5, 5), isNotNull);

      await store.useSource('https://b.example/b.pmtiles');
      expect(await store.getTile(10, 5, 5), isNull,
          reason: 'archive B must not see archive A tiles');
      expect(await store.tileCount(), 0);

      await store.putTile(10, 5, 5, Uint8List.fromList([2, 2]));
      expect((await store.getTile(10, 5, 5))!.length, 2);

      // …and switching back finds the original untouched.
      await store.useSource('https://a.example/a.pmtiles');
      expect((await store.getTile(10, 5, 5))!.length, 3);

      final srcs = await store.sources();
      expect(srcs.map((s) => s.url).toSet(),
          {'https://a.example/a.pmtiles', 'https://b.example/b.pmtiles'});
      expect(srcs.every((s) => s.tiles == 1), isTrue);
    });

    test('deleteSource drops only that archive', () async {
      await store.putTile(9, 1, 1, Uint8List.fromList([1]));
      await store.useSource('https://b.example/b.pmtiles');
      await store.putTile(9, 1, 1, Uint8List.fromList([2]));
      final b = (await store.sources()).firstWhere((s) => s.url.contains('b.'));

      await store.deleteSource(b.id);
      await store.useSource('https://a.example/a.pmtiles');
      expect(await store.getTile(9, 1, 1), isNotNull,
          reason: 'archive A survives deletion of B');
      expect((await store.sources()).length, 1);
    });

    test('route cache round-trips and keys on the request hash', () async {
      final hash = Uint8List.fromList(List.generate(16, (i) => i));
      await store.putRoute(
        requestHash: hash,
        costing: 'auto',
        fromLat: 34.123456, fromLon: -85.654321,
        toLat: 33.7, toLon: -84.4,
        distanceMetres: 143000,
        durationSeconds: 5400,
        shape: '}~kkExyz|N??_pR',
        maneuvers: Uint8List.fromList([0x1f, 0x8b, 1, 2, 3]),
      );

      final got = await store.getRoute(hash);
      expect(got, isNotNull);
      expect(got!.costing, 'auto');
      expect(got.shape, '}~kkExyz|N??_pR');
      expect(got.distanceMetres, 143000);
      expect(got.maneuvers, isNotNull);
      // e6 round-trip keeps the precision the firmware records at.
      expect(got.fromLat, closeTo(34.123456, 1e-6));
      expect(got.fromLon, closeTo(-85.654321, 1e-6));

      expect(await store.getRoute(Uint8List(16)), isNull);
      expect((await store.routeStats()).count, 1);
    });

    test('routes survive a source switch', () async {
      // Routes are not tied to a basemap archive.
      final hash = Uint8List.fromList(List.filled(16, 7));
      await store.putRoute(
        requestHash: hash, costing: 'bicycle',
        fromLat: 1, fromLon: 2, toLat: 3, toLon: 4,
        distanceMetres: 10, durationSeconds: 20, shape: 'abc',
      );
      await store.useSource('https://b.example/b.pmtiles');
      expect(await store.getRoute(hash), isNotNull);
    });

    test('opens in WAL mode so readers never block the writer', () async {
      // Under the default rollback journal a concurrent reader blocks the
      // writer taking EXCLUSIVE, which killed a region download mid-flight with
      // "database is locked".
      final mode = await store.rawJournalMode();
      expect(mode.toLowerCase(), 'wal');
    });

    test('round-trips a tile through the TMS row flip', () async {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      await store.putTile(10, 266, 405, data);

      expect(await store.getTile(10, 266, 405), equals(data));
      expect(await store.hasTile(10, 266, 405), isTrue);
    });

    test('does not confuse a tile with its vertical mirror', () async {
      // y and (2^z - 1 - y) are distinct tiles that map to each other's TMS
      // row; storing one must not make the other appear present.
      const z = 10;
      const y = 405;
      const mirrorY = (1 << z) - 1 - y;
      expect(mirrorY, isNot(equals(y)));

      await store.putTile(z, 266, y, Uint8List.fromList([9]));
      expect(await store.hasTile(z, 266, mirrorY), isFalse);
    });

    test('distinguishes a tombstone from a missing tile', () async {
      await store.putTile(8, 1, 1, Uint8List(0));

      expect(await store.getTile(8, 1, 1), isEmpty); // tombstone
      expect(await store.getTile(8, 2, 2), isNull); // never fetched
    });

    test('reports tile count and byte totals', () async {
      await store.putTiles([
        (z: 5, x: 1, y: 1, data: Uint8List.fromList([1, 2, 3])),
        (z: 5, x: 1, y: 2, data: Uint8List.fromList([4, 5])),
      ]);

      expect(await store.tileCount(), 2);
      expect(await store.totalBytes(), 5);
    });

    test('deleting a region keeps tiles claimed by an overlapping region',
        () async {
      // Two regions sharing a column of tiles; deleting one must not blank the
      // area the other still covers.
      final a = MapRegion.fromBounds(
        name: 'A',
        bounds: LatLngBounds(const LatLng(0, 0), const LatLng(1, 1)),
        minZoom: 8,
        maxZoom: 8,
      );
      final b = MapRegion.fromBounds(
        name: 'B',
        bounds: LatLngBounds(const LatLng(0.5, 0.5), const LatLng(1.5, 1.5)),
        minZoom: 8,
        maxZoom: 8,
      );
      final aId = await store.insertRegion(a);
      await store.insertRegion(b);

      // Seed every tile both regions cover.
      for (final r in [a, b]) {
        for (final t in r.tileRangeForZoom(8).tiles()) {
          await store.putTile(t.z, t.x, t.y, Uint8List.fromList([1]));
        }
      }
      final overlap = b.tileRangeForZoom(8).tiles().where(
            (t) => a.containsTile(t.z, t.x, t.y),
          );
      expect(overlap, isNotEmpty, reason: 'test needs a genuine overlap');

      await store.deleteRegion(aId);

      for (final t in overlap) {
        expect(
          await store.hasTile(t.z, t.x, t.y),
          isTrue,
          reason: 'tile ${t.z}/${t.x}/${t.y} is still inside region B',
        );
      }
      expect((await store.regions()).map((r) => r.name), ['B']);
    });

    test('storedTileKeysInRange finds exactly the stored tiles', () async {
      // The bulk lookup the downloader uses to skip already-held tiles does its
      // own XYZ<->TMS conversion, so it has to agree with putTile's.
      final region = MapRegion.fromBounds(
        name: 'range',
        bounds: LatLngBounds(const LatLng(10, 10), const LatLng(11, 11)),
        minZoom: 9,
        maxZoom: 9,
      );
      final range = region.tileRangeForZoom(9);
      final all = range.tiles().toList();
      expect(all.length, greaterThan(2));

      // Store every other tile in the range.
      final stored = <({int z, int x, int y})>[];
      for (var i = 0; i < all.length; i += 2) {
        stored.add(all[i]);
        await store.putTile(all[i].z, all[i].x, all[i].y, Uint8List.fromList([1]));
      }

      final result = await store.storedTilesInRange(range);

      expect(result.keys.length, stored.length);
      for (final t in all) {
        expect(
          result.keys.contains(MapTileStore.tileKey(t.z, t.x, t.y)),
          stored.contains(t),
          reason: 'tile ${t.z}/${t.x}/${t.y} membership mismatch',
        );
      }
      // One byte per stored tile above — a resumed download seeds its byte
      // total from this, so an undercount would misreport the region size.
      expect(result.bytes, stored.length);
    });

    test('storedTileKeysInRange ignores tiles outside the range', () async {
      final region = MapRegion.fromBounds(
        name: 'narrow',
        bounds: LatLngBounds(const LatLng(10, 10), const LatLng(10.05, 10.05)),
        minZoom: 9,
        maxZoom: 9,
      );
      final range = region.tileRangeForZoom(9);
      // A tile at the same zoom but well outside the box.
      await store.putTile(9, range.maxX + 5, range.maxY + 5, Uint8List.fromList([1]));
      // ...and one at a different zoom entirely.
      await store.putTile(8, range.minX, range.minY, Uint8List.fromList([1]));

      final result = await store.storedTilesInRange(range);
      expect(result.keys, isEmpty);
      expect(result.bytes, 0);
    });

    test('deleting a region removes tiles a distant region does not cover',
        () async {
      // Regression: the survivor scan used to ignore geography, so ANY other
      // region at the same zoom was treated as protecting tiles — which both
      // left tiles behind and forced a slow row-by-row delete.
      final target = MapRegion.fromBounds(
        name: 'target',
        bounds: LatLngBounds(const LatLng(10, 10), const LatLng(11, 11)),
        minZoom: 9,
        maxZoom: 9,
      );
      final faraway = MapRegion.fromBounds(
        name: 'faraway',
        bounds: LatLngBounds(const LatLng(-40, -70), const LatLng(-39, -69)),
        minZoom: 9,
        maxZoom: 9,
      );
      final targetId = await store.insertRegion(target);
      await store.insertRegion(faraway);

      for (final r in [target, faraway]) {
        for (final t in r.tileRangeForZoom(9).tiles()) {
          await store.putTile(t.z, t.x, t.y, Uint8List.fromList([1]));
        }
      }

      await store.deleteRegion(targetId);

      for (final t in target.tileRangeForZoom(9).tiles()) {
        expect(await store.hasTile(t.z, t.x, t.y), isFalse,
            reason: 'tile ${t.z}/${t.x}/${t.y} is not covered by any survivor');
      }
      // The distant region must be untouched.
      for (final t in faraway.tileRangeForZoom(9).tiles()) {
        expect(await store.hasTile(t.z, t.x, t.y), isTrue);
      }
    });

    test('clearAll empties tiles and regions', () async {
      await store.putTile(3, 1, 1, Uint8List.fromList([1]));
      await store.insertRegion(
        MapRegion.fromBounds(
          name: 'X',
          bounds: LatLngBounds(const LatLng(0, 0), const LatLng(1, 1)),
          minZoom: 3,
          maxZoom: 3,
        ),
      );

      await store.clearAll();

      expect(await store.tileCount(), 0);
      expect(await store.regions(), isEmpty);
    });
  });

  group('MapRegion tile math', () {
    test('covers the whole world in one tile at zoom 0', () {
      final world = MapRegion.fromBounds(
        name: 'world',
        bounds: LatLngBounds(const LatLng(-85, -180), const LatLng(85, 180)),
        minZoom: 0,
        maxZoom: 0,
      );
      expect(world.tileRangeForZoom(0).count, 1);
    });

    test('maps a known coordinate to its slippy tile', () {
      // Null Island sits at the top-left of the south-east quadrant: at z1 the
      // world is 2x2 and (0,0) lands on tile x=1, y=1.
      final r = MapRegion.fromBounds(
        name: 'origin',
        bounds: LatLngBounds(const LatLng(0, 0), const LatLng(0, 0)),
        minZoom: 1,
        maxZoom: 1,
      );
      final range = r.tileRangeForZoom(1);
      expect(range.minX, 1);
      expect(range.minY, 1);
    });

    test('totalTiles sums every zoom in the range', () {
      final r = MapRegion.fromBounds(
        name: 'multi',
        bounds: LatLngBounds(const LatLng(0, 0), const LatLng(1, 1)),
        minZoom: 5,
        maxZoom: 8,
      );
      var expected = 0;
      for (var z = 5; z <= 8; z++) {
        expected += r.tileRangeForZoom(z).count;
      }
      expect(r.totalTiles, expected);
      expect(r.totalTiles, greaterThan(4));
    });

    test('clamps tile indices to the world at every zoom', () {
      final r = MapRegion.fromBounds(
        name: 'poles',
        bounds: LatLngBounds(const LatLng(-89, -180), const LatLng(89, 180)),
        minZoom: 4,
        maxZoom: 4,
      );
      final range = r.tileRangeForZoom(4);
      expect(range.minX, greaterThanOrEqualTo(0));
      expect(range.minY, greaterThanOrEqualTo(0));
      expect(range.maxX, lessThan(1 << 4));
      expect(range.maxY, lessThan(1 << 4));
    });

    test('containsTile agrees with the enumerated range', () {
      final r = MapRegion.fromBounds(
        name: 'agree',
        bounds: LatLngBounds(const LatLng(10, 10), const LatLng(11, 11)),
        minZoom: 9,
        maxZoom: 9,
      );
      for (final t in r.tileRangeForZoom(9).tiles()) {
        expect(r.containsTile(t.z, t.x, t.y), isTrue);
      }
      final outside = r.tileRangeForZoom(9);
      expect(r.containsTile(9, outside.maxX + 1, outside.minY), isFalse);
      expect(r.containsTile(8, outside.minX, outside.minY), isFalse);
    });
  });
}
