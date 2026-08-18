import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/utils/polyline_codec.dart';

/// Pinned against a real response from our own Valhalla instance
/// (Atlanta -> Chattanooga, auto costing) rather than a synthetic fixture.
void main() {
  final shape =
      File('test/fixtures/valhalla_shape_atl_cha.txt').readAsStringSync();

  test('decodes a real Valhalla shape at precision 6', () {
    final pts = PolylineCodec.decode(shape);

    expect(pts.length, 2026);
    // Endpoints are what we asked the router for.
    expect(pts.first.latitude, closeTo(33.7490, 0.002));
    expect(pts.first.longitude, closeTo(-84.3880, 0.002));
    expect(pts.last.latitude, closeTo(35.0456, 0.002));
    expect(pts.last.longitude, closeTo(-85.3097, 0.002));
  });

  test('precision 5 would silently land far away', () {
    // The failure this guards: Valhalla uses 1e6 while Google/OSRM use 1e5, and
    // decoding at the wrong one throws nothing — it just scales everything by
    // ten. Worth pinning, because "route is in the wrong hemisphere" is a
    // confusing symptom to trace back to a constant.
    final wrong = PolylineCodec.decode(shape, precision: 5);
    expect((wrong.first.latitude - 33.7490).abs(), greaterThan(100));
  });

  test('round-trips through encode', () {
    const original = [
      LatLng(33.748950, -84.387510),
      LatLng(33.749900, -84.386000),
      LatLng(35.045760, -85.309700),
    ];
    final decoded = PolylineCodec.decode(PolylineCodec.encode(original));
    expect(decoded.length, original.length);
    for (var i = 0; i < original.length; i++) {
      expect(decoded[i].latitude, closeTo(original[i].latitude, 1e-6));
      expect(decoded[i].longitude, closeTo(original[i].longitude, 1e-6));
    }
  });

  test('handles an empty shape', () {
    expect(PolylineCodec.decode(''), isEmpty);
    expect(PolylineCodec.encode(const []), '');
  });

  test('the decoded line is geographically sane', () {
    final pts = PolylineCodec.decode(shape);
    final d = const Distance();
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final step = d(pts[i - 1], pts[i]);
      // No teleports: consecutive shape points are metres apart, not degrees.
      expect(step, lessThan(5000), reason: 'jump at index $i');
      total += step;
    }
    // Valhalla reported 189.9 km for this trip.
    expect(total / 1000, closeTo(189.9, 5));
  });
}
