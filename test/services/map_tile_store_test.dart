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
      await store.open(tmp.path);
    });

    tearDown(() async {
      await store.close();
      await tmp.delete(recursive: true);
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
