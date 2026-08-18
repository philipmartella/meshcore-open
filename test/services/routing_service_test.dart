import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/services/routing_service.dart';

/// Pinned against a real /route response captured from our own Valhalla
/// instance (Atlanta -> Chattanooga, auto costing), so the parser is checked
/// against the wire format rather than against the documentation.
void main() {
  final body =
      File('test/fixtures/valhalla_route_atl_cha.json').readAsStringSync();

  group('parseResponse', () {
    test('extracts geometry, distance, duration and maneuvers', () {
      final r = RoutingService.parseResponse(body, costing: 'auto');

      expect(r.points.length, 2026);
      expect(r.costing, 'auto');
      expect(r.maneuvers.length, 12);
      // Valhalla reported 189.9 km / 107 min for this trip.
      expect(r.distanceKm, closeTo(189.9, 0.5));
      expect(r.duration.inMinutes, closeTo(107, 3));
      expect(r.fromCache, isFalse);
    });

    test('converts summary length from kilometres to metres', () {
      // We request units=kilometers, so `length` is km and the model stores
      // metres. Getting this wrong is a 1000x error that still looks plausible
      // on a map, since the polyline itself is unaffected.
      final r = RoutingService.parseResponse(body, costing: 'auto');
      expect(r.distanceMetres, greaterThan(150000));
      expect(r.distanceMetres, lessThan(250000));
    });

    test('maneuver shape indices address the decoded polyline', () {
      final r = RoutingService.parseResponse(body, costing: 'auto');
      for (final m in r.maneuvers) {
        expect(m.beginShapeIndex, inInclusiveRange(0, r.points.length - 1),
            reason: 'maneuver "${m.instruction}" points outside the shape');
      }
      expect(r.maneuvers.first.beginShapeIndex, 0);
      expect(r.maneuvers.first.instruction, isNotEmpty);
    });

    test('endpoints match what was asked for', () {
      final r = RoutingService.parseResponse(body, costing: 'auto');
      expect(r.points.first.latitude, closeTo(33.7490, 0.002));
      expect(r.points.last.longitude, closeTo(-85.3097, 0.002));
    });
  });

  group('unit handling', () {
    final milesBody = File(
      'test/fixtures/valhalla_route_atl_cha_miles.json',
    ).readAsStringSync();

    test('an imperial response yields the same distance in metres', () {
      // Same journey, requested in different units. Lengths arrive as 189.89
      // and 117.99; both must normalise to the same metres, or the cache would
      // hold two different "truths" for one road.
      final km = RoutingService.parseResponse(body, costing: 'auto');
      final mi = RoutingService.parseResponse(milesBody, costing: 'auto');
      expect(mi.distanceMetres, closeTo(km.distanceMetres, 500));
      expect(mi.distanceMetres, greaterThan(150000));
    });

    test('maneuver distances normalise too', () {
      final km = RoutingService.parseResponse(body, costing: 'auto');
      final mi = RoutingService.parseResponse(milesBody, costing: 'auto');
      expect(mi.maneuvers.length, km.maneuvers.length);
      for (var i = 0; i < km.maneuvers.length; i++) {
        expect(
          mi.maneuvers[i].distanceMetres,
          closeTo(km.maneuvers[i].distanceMetres, 60),
          reason: 'step $i disagrees between unit systems',
        );
      }
    });

    test('guidance prose really is unit-dependent', () {
      // The reason units are part of the cache key rather than a display
      // concern: the server writes distances into the text.
      expect(body, contains('kilometers'));
      expect(milesBody, contains('miles'));
      expect(milesBody, isNot(contains('Continue for 5 kilometers')));
    });
  });

  group('requestHash', () {
    const atl = LatLng(33.7490, -84.3880);
    const cha = LatLng(35.0456, -85.3097);

    test('is stable for the same request', () {
      expect(
        RoutingService.requestHash(from: atl, to: cha, costing: 'auto', units: 'kilometers'),
        RoutingService.requestHash(from: atl, to: cha, costing: 'auto', units: 'kilometers'),
      );
    });

    test('separates costing models', () {
      expect(
        RoutingService.requestHash(from: atl, to: cha, costing: 'auto', units: 'kilometers'),
        isNot(RoutingService.requestHash(from: atl, to: cha, costing: 'bicycle', units: 'kilometers')),
      );
    });

    test('is direction-sensitive', () {
      expect(
        RoutingService.requestHash(from: atl, to: cha, costing: 'auto', units: 'kilometers'),
        isNot(RoutingService.requestHash(from: cha, to: atl, costing: 'auto', units: 'kilometers')),
      );
    });

    test('rounds to microdegrees so near-identical taps share a route', () {
      // Sub-microdegree jitter is ~10 cm; caching those separately would fill
      // the store with duplicates of the same journey.
      const jittered = LatLng(33.74900004, -84.38800004);
      expect(
        RoutingService.requestHash(from: atl, to: cha, costing: 'auto', units: 'kilometers'),
        RoutingService.requestHash(from: jittered, to: cha, costing: 'auto', units: 'kilometers'),
      );
    });

    test('distinguishes genuinely different places', () {
      const elsewhere = LatLng(33.7600, -84.3880);
      expect(
        RoutingService.requestHash(from: atl, to: cha, costing: 'auto', units: 'kilometers'),
        isNot(RoutingService.requestHash(from: elsewhere, to: cha, costing: 'auto', units: 'kilometers')),
      );
    });

    test('separates unit systems', () {
      // Valhalla writes distances into the guidance prose, so a metric route
      // replayed under imperial would read in the wrong unit.
      expect(
        RoutingService.requestHash(
            from: atl, to: cha, costing: 'auto', units: 'kilometers'),
        isNot(RoutingService.requestHash(
            from: atl, to: cha, costing: 'auto', units: 'miles')),
      );
    });

    test('is a 16-byte key', () {
      expect(
        RoutingService.requestHash(from: atl, to: cha, costing: 'auto', units: 'kilometers').length,
        16,
      );
    });
  });
}
