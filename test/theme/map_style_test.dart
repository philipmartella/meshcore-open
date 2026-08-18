import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// ThemeReader drops any layer it cannot parse, silently — a style that is
/// malformed, or that uses an expression the renderer does not implement,
/// renders as absence rather than an error. These assert the styles survive
/// parsing intact, which is the failure mode that costs the most time to spot.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const styles = {
    'light': 'assets/map/omt_light.json',
    'dark': 'assets/map/omt_dark.json',
  };

  // Every layer we author, including the labels.
  const expected = {
    'background', 'landcover', 'landuse', 'park', 'water',
    'roads_casing', 'roads_minor', 'roads_major', 'buildings', 'boundaries',
    'label_state', 'label_city', 'label_town', 'label_village',
    'label_road', 'label_water',
  };

  Future<Map<String, dynamic>> load(String path) async =>
      jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>;

  for (final entry in styles.entries) {
    group('${entry.key} style', () {
      test('every authored layer survives ThemeReader', () async {
        final json = await load(entry.value);
        final authored = {
          for (final l in json['layers'] as List) (l as Map)['id'] as String,
        };
        expect(authored, expected,
            reason: 'style file does not contain the expected layer set');

        final theme = vtr.ThemeReader().read(json);
        final parsed = theme.layers.map((l) => l.id).toSet();
        final dropped = authored.difference(parsed);
        expect(dropped, isEmpty,
            reason: 'ThemeReader dropped ${dropped.toList()} — these render '
                'as nothing with no error');
      });

      test('declares a distinct id and the openmaptiles source', () async {
        final json = await load(entry.value);
        expect(json['id'], isNotNull,
            reason: 'without an id the render cache keys collide across themes');
        final sources = {
          for (final l in json['layers'] as List)
            if ((l as Map).containsKey('source')) l['source'] as String,
        };
        expect(sources, {'openmaptiles'});
      });

      test('label text-field reads the attribute the tiles actually carry',
          () async {
        // Regression guard. tilemaker's SetNameAttributes() emits `name:latin`
        // and never a bare `name`; a text-field of ["get","name"] parses fine,
        // evaluates to null, and renders nothing at all — no warning anywhere.
        // Verified against real tiles: place, transportation_name, water_name,
        // park, poi and waterway all expose only `name:latin`.
        final json = await load(entry.value);
        var checked = 0;
        for (final l in json['layers'] as List) {
          final m = l as Map;
          if (m['type'] != 'symbol') continue;
          final field = (m['layout'] as Map)['text-field'];
          expect(field.toString(), contains('name:latin'),
              reason: '${m['id']} must read name:latin, not a bare name');
          checked++;
        }
        expect(checked, greaterThan(0), reason: 'no symbol layers found');
      });

      test('label layers carry a halo', () async {
        final json = await load(entry.value);
        for (final l in json['layers'] as List) {
          final m = l as Map;
          if (!(m['id'] as String).startsWith('label_')) continue;
          final paint = m['paint'] as Map;
          expect(paint['text-halo-color'], isNotNull, reason: '${m['id']}');
          expect(paint['text-halo-width'], isNotNull, reason: '${m['id']}');
        }
      });
    });
  }

  test('the two styles are structurally identical', () async {
    final l = await load(styles['light']!);
    final d = await load(styles['dark']!);
    expect(
      (l['layers'] as List).map((e) => (e as Map)['id']).toList(),
      (d['layers'] as List).map((e) => (e as Map)['id']).toList(),
    );
    expect(l['id'], isNot(d['id']));
  });
}
