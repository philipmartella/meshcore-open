import 'dart:math' as math;

// LatLngBounds is flutter_map's; LatLng is latlong2's. Both are plain data
// types, so the model stays widget-free despite the flutter_map import.
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// A rectangular area of the basemap the user has pre-downloaded (or is
/// downloading) into the offline tile store.
///
/// Bounds are plain WGS84 degrees; [minZoom]/[maxZoom] are inclusive. The
/// tile-enumeration helpers here are the single source of truth for "which
/// tiles does this region contain", used both for size estimates before a
/// download and for the download itself.
class MapRegion {
  final int? id;
  final String name;
  final double west;
  final double south;
  final double east;
  final double north;
  final int minZoom;
  final int maxZoom;

  /// Tiles actually stored so far (updated as a download progresses).
  final int tileCount;

  /// Bytes actually stored so far.
  final int bytes;

  final DateTime createdAt;

  /// False while a download is in flight or was interrupted.
  final bool complete;

  const MapRegion({
    this.id,
    required this.name,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.minZoom,
    required this.maxZoom,
    this.tileCount = 0,
    this.bytes = 0,
    required this.createdAt,
    this.complete = false,
  });

  LatLngBounds get bounds =>
      LatLngBounds(LatLng(south, west), LatLng(north, east));

  factory MapRegion.fromBounds({
    int? id,
    required String name,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    int tileCount = 0,
    int bytes = 0,
    DateTime? createdAt,
    bool complete = false,
  }) => MapRegion(
    id: id,
    name: name,
    west: bounds.west,
    south: bounds.south,
    east: bounds.east,
    north: bounds.north,
    minZoom: minZoom,
    maxZoom: maxZoom,
    tileCount: tileCount,
    bytes: bytes,
    createdAt: createdAt ?? DateTime.now(),
    complete: complete,
  );

  MapRegion copyWith({
    int? id,
    String? name,
    int? tileCount,
    int? bytes,
    bool? complete,
  }) => MapRegion(
    id: id ?? this.id,
    name: name ?? this.name,
    west: west,
    south: south,
    east: east,
    north: north,
    minZoom: minZoom,
    maxZoom: maxZoom,
    tileCount: tileCount ?? this.tileCount,
    bytes: bytes ?? this.bytes,
    createdAt: createdAt,
    complete: complete ?? this.complete,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'name': name,
    'west': west,
    'south': south,
    'east': east,
    'north': north,
    'min_zoom': minZoom,
    'max_zoom': maxZoom,
    'tile_count': tileCount,
    'bytes': bytes,
    'created_at': createdAt.millisecondsSinceEpoch,
    'complete': complete ? 1 : 0,
  };

  factory MapRegion.fromRow(Map<String, Object?> row) => MapRegion(
    id: row['id'] as int?,
    name: row['name'] as String? ?? '',
    west: (row['west'] as num).toDouble(),
    south: (row['south'] as num).toDouble(),
    east: (row['east'] as num).toDouble(),
    north: (row['north'] as num).toDouble(),
    minZoom: (row['min_zoom'] as num).toInt(),
    maxZoom: (row['max_zoom'] as num).toInt(),
    tileCount: (row['tile_count'] as num?)?.toInt() ?? 0,
    bytes: (row['bytes'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (row['created_at'] as num?)?.toInt() ?? 0,
    ),
    complete: ((row['complete'] as num?)?.toInt() ?? 0) != 0,
  );

  /// True when tile z/x/y (XYZ convention) falls inside this region.
  bool containsTile(int z, int x, int y) {
    if (z < minZoom || z > maxZoom) return false;
    final r = tileRangeForZoom(z);
    return x >= r.minX && x <= r.maxX && y >= r.minY && y <= r.maxY;
  }

  /// Inclusive XYZ tile range covering this region at [z].
  TileRange tileRangeForZoom(int z) {
    final n = 1 << z;
    int clampT(int v) => v.clamp(0, n - 1);
    return TileRange(
      z: z,
      minX: clampT(_lonToTileX(west, z)),
      maxX: clampT(_lonToTileX(east, z)),
      // Tile Y grows southward, so the north edge yields the smaller index.
      minY: clampT(_latToTileY(north, z)),
      maxY: clampT(_latToTileY(south, z)),
    );
  }

  /// Total tiles this region covers across its whole zoom range.
  int get totalTiles {
    int sum = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      sum += tileRangeForZoom(z).count;
    }
    return sum;
  }

  /// Tiles covered by [bounds] over an inclusive zoom range — used for
  /// estimates before a region row exists.
  static int estimateTiles(LatLngBounds bounds, int minZoom, int maxZoom) =>
      MapRegion.fromBounds(
        name: '',
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
      ).totalTiles;

  static int _lonToTileX(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();

  static int _latToTileY(double lat, int z) {
    // Web Mercator is undefined at the poles; clamp to the standard limit.
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    final rad = clamped * math.pi / 180.0;
    return ((1 -
                math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
            2 *
            (1 << z))
        .floor();
  }
}

/// An inclusive rectangle of XYZ tile indices at one zoom level.
class TileRange {
  final int z;
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  const TileRange({
    required this.z,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  int get count => (maxX - minX + 1) * (maxY - minY + 1);

  Iterable<({int z, int x, int y})> tiles() sync* {
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        yield (z: z, x: x, y: y);
      }
    }
  }
}
