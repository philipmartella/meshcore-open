import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/battery_indicator.dart';
import 'package:meshcore_open/widgets/signal_ui.dart';

/// The palette's accents were chosen against the near-black dark surface. Used
/// unchanged on the light surface they land around 2.0-2.6:1, which is what
/// made light mode look second-class. These pin the resolver that fixes it.
void main() {
  final light = MeshTheme.light().colorScheme;
  final dark = MeshTheme.dark().colorScheme;

  // Every semantic accent the app paints as text/icons on a tint of itself.
  const accents = <String, Color>{
    'signal': MeshPalette.signal,
    'warn': MeshPalette.warn,
    'alert': MeshPalette.alert,
    'magenta': MeshPalette.magenta,
    'blue': MeshPalette.blue,
    'warnDim': MeshPalette.warnDim,
    'signalDim': MeshPalette.signalDim,
  };

  group('contrastRatio', () {
    test('matches known WCAG values', () {
      expect(
        MeshTheme.contrastRatio(Colors.white, Colors.black),
        closeTo(21.0, 0.01),
      );
      expect(
        MeshTheme.contrastRatio(Colors.white, Colors.white),
        closeTo(1.0, 0.01),
      );
    });

    test('is symmetric', () {
      expect(
        MeshTheme.contrastRatio(MeshPalette.warn, MeshPalette.lightBg),
        closeTo(
          MeshTheme.contrastRatio(MeshPalette.lightBg, MeshPalette.warn),
          0.001,
        ),
      );
    });
  });

  group('readableOnTint — light mode', () {
    for (final entry in accents.entries) {
      test('${entry.key} clears AA on its own tint', () {
        final tint = Color.alphaBlend(
          entry.value.withValues(alpha: 0.12),
          light.surface,
        );
        final resolved = MeshTheme.readableOnTint(entry.value, light);
        expect(
          MeshTheme.contrastRatio(resolved, tint),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} would be unreadable on a light chip',
        );
      });
    }

    test('actually changes the washed-out accents', () {
      // Regression guard: if these came back unchanged the resolver is not
      // being applied and light mode is broken again.
      for (final key in ['warn', 'signal', 'magenta', 'blue']) {
        final accent = accents[key]!;
        expect(
          MeshTheme.readableOnTint(accent, light),
          isNot(equals(accent)),
          reason: '$key needed adjusting for light mode',
        );
      }
    });

    test('preserves hue', () {
      for (final entry in accents.entries) {
        final before = HSLColor.fromColor(entry.value).hue;
        final after = HSLColor.fromColor(
          MeshTheme.readableOnTint(entry.value, light),
        ).hue;
        expect(
          after,
          closeTo(before, 1.0),
          reason: '${entry.key} changed hue — amber must stay amber',
        );
      }
    });
  });

  group('readableOnTint — dark mode', () {
    test('accents clear AA on their own tint', () {
      for (final entry in accents.entries) {
        final tint = Color.alphaBlend(
          entry.value.withValues(alpha: 0.12),
          dark.surface,
        );
        expect(
          MeshTheme.contrastRatio(
            MeshTheme.readableOnTint(entry.value, dark),
            tint,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} unreadable on a dark chip',
        );
      }
    });

    test('leaves the dark look essentially alone', () {
      // The accents were tuned for this surface, so any correction here should
      // be imperceptible — a large shift would mean the dark palette drifted.
      for (final entry in accents.entries) {
        final resolved = MeshTheme.readableOnTint(entry.value, dark);
        final before = HSLColor.fromColor(entry.value);
        final after = HSLColor.fromColor(resolved);
        expect(
          (after.lightness - before.lightness).abs(),
          lessThan(0.10),
          reason: '${entry.key} shifted too far in dark mode',
        );
      }
    });
  });

  group('semantic helpers resolve for the surface they draw on', () {
    test('snrColor clears AA in both modes when given a scheme', () {
      for (final snr in <num?>[null, 4, -8, -20]) {
        for (final scheme in [light, dark]) {
          expect(
            MeshTheme.contrastRatio(
              MeshTheme.snrColor(snr, blocked: false, scheme: scheme),
              scheme.surface,
            ),
            greaterThanOrEqualTo(4.5),
            reason: 'snr=$snr unreadable',
          );
        }
      }
    });

    test('snrColor without a scheme keeps the raw palette value', () {
      // Map panels are deliberately dark and want the unresolved ramp.
      expect(MeshTheme.snrColor(4, blocked: false), MeshPalette.signal);
      expect(MeshTheme.snrColor(null, blocked: true), MeshPalette.alert);
    });

    test('signalUiForStrengthTier clears AA in both modes', () {
      for (var tier = 0; tier <= 4; tier++) {
        for (final scheme in [light, dark]) {
          expect(
            MeshTheme.contrastRatio(
              signalUiForStrengthTier(tier, scheme: scheme).color,
              scheme.surface,
            ),
            greaterThanOrEqualTo(4.5),
            reason: 'tier $tier unreadable',
          );
        }
      }
    });

    test('batteryUiForPercent clears AA in both modes', () {
      for (final pct in [3, 10, 25, 40, 55, 70, 100]) {
        for (final scheme in [light, dark]) {
          final color = batteryUiForPercent(pct, scheme: scheme).color;
          if (color == null) continue; // inherits the ambient icon color
          expect(
            MeshTheme.contrastRatio(color, scheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$pct% unreadable',
          );
        }
      }
    });
  });

  group('avatar / sender identity hues', () {
    // Hand-picked per brightness rather than resolved, precisely so distinct
    // people keep distinct colors. These guard the properties that buys.
    const tintAlpha = 0.14;

    double hueOf(Color c) => HSLColor.fromColor(c).hue;

    for (final (mode, hues, scheme) in [
      ('dark', MeshPalette.avatarHuesDark, dark),
      ('light', MeshPalette.avatarHuesLight, light),
    ]) {
      test('$mode hues are legible on the avatar tint', () {
        for (final h in hues) {
          final tint = Color.alphaBlend(
            h.withValues(alpha: tintAlpha),
            scheme.surface,
          );
          expect(
            MeshTheme.contrastRatio(h, tint),
            greaterThanOrEqualTo(4.5),
            reason: '$h unreadable on its own $mode avatar tint',
          );
        }
      });

      test('$mode hues are legible on a chat bubble', () {
        for (final h in hues) {
          expect(
            MeshTheme.contrastRatio(h, scheme.surfaceContainerLow),
            greaterThanOrEqualTo(4.5),
            reason: '$h unreadable as a $mode sender label',
          );
        }
      });

      test('$mode hues stay far enough apart to tell people apart', () {
        final sorted = hues.map(hueOf).toList()..sort();
        for (var i = 0; i < sorted.length; i++) {
          final gap =
              (sorted[(i + 1) % sorted.length] - sorted[i]) % 360;
          expect(
            gap,
            greaterThanOrEqualTo(40.0),
            reason: 'two $mode identity hues are only ${gap.round()}° apart',
          );
        }
      });
    }

    test('the two sets are index-aligned so identity survives a theme switch', () {
      expect(
        MeshPalette.avatarHuesLight.length,
        MeshPalette.avatarHuesDark.length,
      );
      for (final name in ['Alice', 'bob', 'CoffeeBean 228', '', '🛰️ node']) {
        final li = MeshPalette.avatarHuesLight.indexOf(
          MeshPalette.avatarHueFor(name, Brightness.light),
        );
        final di = MeshPalette.avatarHuesDark.indexOf(
          MeshPalette.avatarHueFor(name, Brightness.dark),
        );
        expect(li, di, reason: '"$name" changes identity slot across themes');
      }
    });

    test('the hue is stable for a given name', () {
      expect(
        MeshPalette.avatarHueFor('CoffeeBean 228', Brightness.dark),
        MeshPalette.avatarHueFor('CoffeeBean 228', Brightness.dark),
      );
    });
  });

  group('readableOn handles arbitrary call-site colors', () {
    test('Material swatches and one-off hues clear AA on light surfaces', () {
      // Call sites pass colors the palette does not own (per-contact hues, the
      // sensor teal), which is why the resolver is algorithmic rather than a
      // token lookup.
      const arbitrary = <Color>[
        MeshPalette.teal,
        Color(0xFF8FA8F0), // avatar pastel
        Color(0xFF6FD9CE), // avatar pastel
        Colors.blue,
        Colors.orange,
        Colors.teal,
        Colors.green,
      ];
      for (final c in arbitrary) {
        expect(
          MeshTheme.contrastRatio(
            MeshTheme.readableOn(c, light.surface),
            light.surface,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$c unreadable on the light surface',
        );
      }
    });

    test('terminates on a fully desaturated input', () {
      // Grey cannot reach AA by shifting hue, so the fallback must engage.
      final resolved = MeshTheme.readableOn(
        const Color(0xFF808080),
        light.surface,
      );
      expect(
        MeshTheme.contrastRatio(resolved, light.surface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('AMPM map overlays vs the basemap they sit on', () {
    // Sampled from assets/map/protomaps_{light,dark}.json — the largest areas
    // an overlay is drawn over.
    const lightEarth = Color(0xFFE8E6E0);
    const darkEarth = Color(0xFF131C2C);

    const pairs = <String, (Color onLight, Color onDark)>{
      'gpsTrack': (MapPalette.gpsTrackOnLight, MapPalette.gpsTrackOnDark),
      'gpsTrackStart': (
        MapPalette.gpsTrackStartOnLight,
        MapPalette.gpsTrackStartOnDark,
      ),
      'flockYou': (MapPalette.flockYouOnLight, MapPalette.flockYouOnDark),
    };

    for (final entry in pairs.entries) {
      test('${entry.key} is visible on both basemap styles', () {
        // 3:1 is the WCAG bar for graphical objects; a single value cannot
        // clear it on both styles, which is why these are pairs.
        expect(
          MeshTheme.contrastRatio(entry.value.$1, lightEarth),
          greaterThanOrEqualTo(3.0),
          reason: '${entry.key} washes out on the light basemap',
        );
        expect(
          MeshTheme.contrastRatio(entry.value.$2, darkEarth),
          greaterThanOrEqualTo(3.0),
          reason: '${entry.key} disappears into the dark basemap',
        );
      });

      test('${entry.key} marker glyph reads on its fill', () {
        for (final fill in [entry.value.$1, entry.value.$2]) {
          expect(
            MeshTheme.contrastRatio(MeshTheme.onColor(fill), fill),
            greaterThanOrEqualTo(4.5),
            reason: 'glyph unreadable on $fill',
          );
        }
      });
    }

    test('forBasemap selects by brightness', () {
      expect(
        MapPalette.forBasemap(
          Brightness.dark,
          onLight: MapPalette.gpsTrackOnLight,
          onDark: MapPalette.gpsTrackOnDark,
        ),
        MapPalette.gpsTrackOnDark,
      );
      expect(
        MapPalette.forBasemap(
          Brightness.light,
          onLight: MapPalette.gpsTrackOnLight,
          onDark: MapPalette.gpsTrackOnDark,
        ),
        MapPalette.gpsTrackOnLight,
      );
    });
  });

  group('base schemes', () {
    test('light surface/onSurface and dark surface/onSurface both clear AA', () {
      expect(
        MeshTheme.contrastRatio(light.onSurface, light.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        MeshTheme.contrastRatio(dark.onSurface, dark.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        MeshTheme.contrastRatio(light.onSurfaceVariant, light.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        MeshTheme.contrastRatio(dark.onSurfaceVariant, dark.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('error snackbars are legible in both modes', () {
      // Regression guard for the SnackBar contentTextStyle fix.
      expect(
        MeshTheme.contrastRatio(light.onError, light.error),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        MeshTheme.contrastRatio(dark.onError, dark.error),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
