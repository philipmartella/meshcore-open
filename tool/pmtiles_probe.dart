// Standalone probe: validates that pmtiles can read a self-hosted archive over
// HTTP range (header, leaf-directory traversal at max zoom, gzip tiles).
//
// It CANNOT be run with `dart run` from this project — meshcore-open has native
// build hooks (llamadart) that only build under Flutter's toolchain. Copy this
// file into a throwaway pure-Dart package that depends only on pmtiles, then:
//   dart pub get && dart run bin/probe.dart
// Not part of the app build — a diagnostic for re-validating a new extract.
import 'package:pmtiles/pmtiles.dart';

const url = 'http://localhost:8088/tiles/se10-z15.pmtiles';

// (z, x, y) tiles over Atlanta (~33.75N, -84.39W): a low zoom, a mid zoom,
// and a max zoom (z15) to force leaf-directory traversal on the big archive.
const probes = <(int, int, int)>[
  (4, 4, 6),
  (8, 68, 101),
  (10, 272, 406),
  (15, 8703, 12996),
];

Future<int> main() async {
  print('opening $url ...');
  final archive = await PmTilesArchive.from(url);
  try {
    print('  tileType   = ${archive.tileType}');
    print('  compression= ${archive.tileCompression}');
    print('  zoom       = ${archive.minZoom}..${archive.maxZoom}');
    print('  bounds     = ${archive.minPosition} .. ${archive.maxPosition}');
    print('');
    for (final (z, x, y) in probes) {
      final id = ZXY(z, x, y).toTileId();
      try {
        final t = await archive.tile(id);
        final raw = t.compressedBytes().length;
        final dec = t.bytes().length; // exercises gzip decode
        print('  z$z/$x/$y  id=$id  compressed=$raw B  decoded=$dec B  OK');
      } on TileNotFoundException {
        print('  z$z/$x/$y  id=$id  (not present)');
      }
    }
  } finally {
    await archive.close();
  }
  return 0;
}
