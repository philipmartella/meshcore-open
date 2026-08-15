import 'package:flutter/material.dart';

/// MeshCore palette — high-contrast slate surfaces with sky-blue accents.
class MeshPalette {
  MeshPalette._();

  // Surfaces shared with the map overlays and navigation.
  static const bg = Color(0xFF0B1220);
  static const bg1 = Color(0xFF0F172A);
  static const bg2 = Color(0xFF162033);
  static const bg3 = Color(0xFF1E293B);
  static const bg4 = Color(0xFF334155);

  // Lines — lifted for clearer element separation on the near-black surface
  static const line = Color(0xFF2A3850);
  static const line2 = Color(0xFF3B4A61);
  static const line3 = Color(0xFF546376);

  // Ink — muted tones brightened for readable secondary/tertiary text in dark
  static const ink = Color(0xFFF8FAFC);
  static const ink2 = Color(0xFFD5DEE9);
  static const ink3 = Color(0xFFAAB6C6);
  static const ink4 = Color(0xFF828FA3);

  // Signal-quality green (used only for SNR coloring, not UI chrome)
  static const signal = Color(0xFF22C55E);
  static const signalDim = Color(0xFF16A34A);

  // Warn
  static const warn = Color(0xFFF59E0B);
  static const warnDim = Color(0xFFD97706);
  static const warnBg = Color(0x1FF59E0B);
  static const warnLine = Color(0x66F59E0B);

  // Alert
  static const alert = Color(0xFFEF4444);
  static const alertBg = Color(0x1FEF4444);
  static const alertLine = Color(0x66EF4444);

  // Blue — primary map/app accent
  static const blue = Color(0xFF0EA5E9);
  static const blueDim = Color(0xFF0284C7);
  static const blueBg = Color(0x290EA5E9);
  static const blueLine = Color(0x800EA5E9);

  // Teal — sensor nodes
  static const teal = Color(0xFF4ACCC4);

  // Magenta
  static const magenta = Color(0xFFDE7FDB);
  static const magentaBg = Color(0x1CDE7FDB);
  static const magentaLine = Color(0x47DE7FDB);

  // Me bubble (dusk blue)
  static const me = Color(0xFF0C4A6E);
  static const meBorder = Color(0xFF0369A1);
  static const meInk = Color(0xFFF0F9FF);

  // ── Light variant (used when user explicitly picks light theme)
  static const lightBg = Color(0xFFF4F6F8);
  static const lightBg1 = Color(0xFFEAEEF2);
  static const lightBg2 = Color(0xFFDFE5EA);
  static const lightLine = Color(0xFFC3CCD4);
  static const lightInk = Color(0xFF10161B);
  static const lightInk2 = Color(0xFF3C4853);
  static const lightInk3 = Color(0xFF69767F);
  static const lightBlue = Color(0xFF2F6EA8);
}

/// High-contrast semantic colors for UI rendered over variable map tiles.
class MapPalette {
  MapPalette._();

  static const online = Color(0xFF22C55E);
  static const offline = Color(0xFF6B7280);
  static const stale = Color(0xFFF59E0B);
  static const repeater = Color(0xFF2563EB);
  static const router = Color(0xFF7C3AED);
  static const batteryLow = Color(0xFFEF4444);
  static const cluster = Color(0xFFF97316);
  static const selected = Color(0xFF0EA5E9);
  static const sensor = Color(0xFF0F766E);
  static const shared = Color(0xFF0369A1);

  /// AMPM overlays — deliberately distinct from the node/contact markers above
  /// so a track or a camera is never mistaken for a mesh node.
  ///
  /// These are the one place a single color genuinely cannot serve both
  /// basemaps: the mid-cyan that reads at 7:1 on the dark style drops to 1.9:1
  /// on the pale one. Each therefore comes as a pair, picked by [forBasemap].
  static const gpsTrackOnLight = Color(0xFF0E7490);
  static const gpsTrackOnDark = Color(0xFF22D3EE);
  static const gpsTrackStartOnLight = Color(0xFF15803D);
  static const gpsTrackStartOnDark = Color(0xFF4ADE80);
  static const flockYouOnLight = Color(0xFFB91C1C);
  static const flockYouOnDark = Color(0xFFF87171);

  /// Picks the variant tuned for the basemap style in use.
  static Color forBasemap(
    Brightness brightness, {
    required Color onLight,
    required Color onDark,
  }) => brightness == Brightness.dark ? onDark : onLight;

  static const panelLight = Color(0xF0FFFFFF);
  static const panelDark = Color(0xF50B1220);
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFFCBD5E1);
  static const textMuted = Color(0xFF94A3B8);
  static const border = Color(0x5264758B);
  static const markerOutline = Colors.white;
  static const markerShadow = Color(0xB3000000);
}

/// High-contrast colors for line-of-sight maps and elevation profiles.
class LosPalette {
  LosPalette._();

  static const terrain = Color(0xFFA3E635);
  static const beam = Color(0xFF38BDF8);
  static const horizon = Color(0xFFFBBF24);
  static const blocked = Color(0xFFEF4444);
  static const marginal = Color(0xFFF59E0B);
  static const clear = Color(0xFF22C55E);
  static const selected = Color(0xFF0EA5E9);
  static const chartBackground = Color(0xFF0B1220);
  static const panelDark = Color(0xF00F172A);
  static const panelLight = Color(0xF5FFFFFF);
  static const text = Color(0xFFF8FAFC);
  static const textMuted = Color(0xFFCBD5E1);
  static const border = Color(0x5264758B);
  static const shadow = Color(0x99000000);
}

/// Named font stacks — Flutter falls back to system fonts when the named
/// family isn't installed, keeping things working without bundled assets.
class MeshFonts {
  MeshFonts._();

  static const sans = 'Inter';
  static const mono = 'JetBrains Mono';
  static const display = 'Instrument Serif';
  static const emoji = 'Noto Color Emoji';

  static const List<String> sansFallback = [
    'system-ui',
    '-apple-system',
    'Roboto',
    'Noto Sans',
    'sans-serif',
  ];
  static const List<String> monoFallback = [
    'SF Mono',
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'monospace',
  ];
  static const List<String> displayFallback = [
    'Cormorant Garamond',
    'Georgia',
    'Times New Roman',
    'serif',
  ];
  static const List<String> emojiFallback = [
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Noto Emoji',
  ];
}

/// Radii used consistently across the app.
class MeshRadii {
  MeshRadii._();
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

/// Shared helpers exposed via [MeshTheme.of].
class MeshTheme {
  MeshTheme._();

  /// WCAG contrast ratio between two opaque colors (1.0 – 21.0).
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Minimum contrast for accent text/icons. WCAG AA for normal text.
  static const double _minAccentContrast = 4.5;

  /// Returns [accent] adjusted until it is legible on [background], preserving
  /// its hue.
  ///
  /// The palette's accents (`signal`, `warn`, `alert`, `magenta`, `blue`) were
  /// picked against the near-black dark surface. Used unchanged on the light
  /// surface they land around 2.0–2.6:1 — amber and green in particular become
  /// nearly invisible. Rather than maintaining a parallel set of light tokens
  /// (which could not cover the arbitrary colors call sites also pass — Material
  /// swatches, per-contact hues), this walks lightness toward the far end until
  /// the ratio clears AA. It is a no-op whenever the color already passes, so
  /// dark mode is untouched.
  static Color readableOn(
    Color accent,
    Color background, {
    double minContrast = _minAccentContrast,
  }) {
    if (contrastRatio(accent, background) >= minContrast) return accent;
    // Darken against a light background, lighten against a dark one.
    final darken = background.computeLuminance() > 0.5;
    var hsl = HSLColor.fromColor(accent);
    for (var i = 0; i < 25; i++) {
      final next = darken ? hsl.lightness - 0.04 : hsl.lightness + 0.04;
      if (next <= 0.0 || next >= 1.0) break;
      hsl = hsl.withLightness(next);
      final candidate = hsl.toColor();
      if (contrastRatio(candidate, background) >= minContrast) return candidate;
    }
    // Hue could not carry the ratio (very desaturated input) — fall back to a
    // guaranteed-legible extreme rather than shipping unreadable text.
    return darken ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);
  }

  /// [readableOn] against the ambient surface — the common case for an accent
  /// icon or label sitting directly on a screen.
  static Color accent(BuildContext context, Color color) =>
      readableOn(color, Theme.of(context).colorScheme.surface);

  /// A glyph color that reads on a solid [fill] — used for icons inside filled
  /// map markers, whose fill varies with the basemap.
  ///
  /// Picks whichever of white/near-black actually contrasts better rather than
  /// thresholding on luminance: mid-tones like a light red sit where a naive
  /// cutoff chooses white and lands under 3:1, while the dark ink would have
  /// cleared 6:1.
  static Color onColor(Color fill) {
    const ink = Color(0xFF0B1220);
    return contrastRatio(Colors.white, fill) >= contrastRatio(ink, fill)
        ? Colors.white
        : ink;
  }

  /// [readableOn] against the tinted chip/avatar fill these widgets paint —
  /// `accent` at [tintAlpha] over the surface, not the raw surface.
  static Color readableOnTint(
    Color accent,
    ColorScheme scheme, {
    double tintAlpha = 0.12,
  }) => readableOn(
    accent,
    Color.alphaBlend(accent.withValues(alpha: tintAlpha), scheme.surface),
  );

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: MeshPalette.blue,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF075985),
      onPrimaryContainer: Colors.white,
      secondary: MeshPalette.magenta,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFF331A33),
      onSecondaryContainer: Colors.white,
      tertiary: MeshPalette.warn,
      onTertiary: Color(0xFF0B1220),
      tertiaryContainer: Color(0xFF78350F),
      onTertiaryContainer: Colors.white,
      // ColorScheme.error carries two roles: a fill that onError sits on, and
      // error text drawn straight onto the surface. White on MeshPalette.alert
      // was only 3.8:1, so the dark scheme follows the Material 3 convention of
      // a lighter error with dark onError — 5.8:1 as a fill, 6.8:1 as text on
      // the dark surface. MeshPalette.alert itself is unchanged for direct use.
      error: Color(0xFFF87171),
      onError: Color(0xFF450A0A),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Colors.white,
      surface: MeshPalette.bg,
      onSurface: MeshPalette.ink,
      surfaceContainerLowest: MeshPalette.bg,
      surfaceContainerLow: MeshPalette.bg1,
      surfaceContainer: MeshPalette.bg1,
      surfaceContainerHigh: MeshPalette.bg2,
      surfaceContainerHighest: MeshPalette.bg3,
      onSurfaceVariant: MeshPalette.ink2,
      outline: MeshPalette.line2,
      outlineVariant: MeshPalette.line,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: MeshPalette.ink,
      onInverseSurface: MeshPalette.bg,
      inversePrimary: MeshPalette.blueDim,
    );
    return _build(scheme, Brightness.dark);
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: MeshPalette.lightBlue,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD3E4F5),
      onPrimaryContainer: Color(0xFF12354F),
      secondary: Color(0xFF8C4A8A),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEFD6EE),
      onSecondaryContainer: Color(0xFF3D1A3C),
      tertiary: Color(0xFF9A5B16),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFF8E3C9),
      onTertiaryContainer: Color(0xFF4A2A05),
      error: Color(0xFFB53D2F),
      onError: Colors.white,
      errorContainer: Color(0xFFF6D9D4),
      onErrorContainer: Color(0xFF5C1A12),
      surface: MeshPalette.lightBg,
      onSurface: MeshPalette.lightInk,
      surfaceContainerLowest: MeshPalette.lightBg,
      surfaceContainerLow: MeshPalette.lightBg1,
      surfaceContainer: MeshPalette.lightBg1,
      surfaceContainerHigh: MeshPalette.lightBg2,
      surfaceContainerHighest: Color(0xFFD2DAE1),
      onSurfaceVariant: MeshPalette.lightInk2,
      outline: MeshPalette.lightLine,
      outlineVariant: Color(0xFFD8DEE5),
      // Set explicitly rather than falling back to the M2 baselines, so the two
      // schemes stay symmetrical — dark() defines all of these.
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: MeshPalette.lightInk,
      onInverseSurface: MeshPalette.lightBg,
      inversePrimary: Color(0xFF9BC4EA),
    );
    return _build(scheme, Brightness.light);
  }

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final baseText =
        Typography.material2021(
          platform: TargetPlatform.android,
          colorScheme: scheme,
        ).black.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      fontFamily: MeshFonts.sans,
      fontFamilyFallback: MeshFonts.sansFallback,
      textTheme: baseText,
      dividerColor: scheme.outlineVariant,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
        shape: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.pill),
        ),
        extendedTextStyle: const TextStyle(
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeshRadii.pill),
          ),
          textStyle: const TextStyle(
            fontFamily: MeshFonts.sans,
            fontFamilyFallback: MeshFonts.sansFallback,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeshRadii.pill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeshRadii.pill),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: MeshFonts.sans,
            fontFamilyFallback: MeshFonts.sansFallback,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.1,
            // The label sits below the indicator pill, on the bar background —
            // not inside it — so onPrimary would be white text on a light
            // surface. The icon above it is the part that gets onPrimary.
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            size: 22,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(MeshRadii.lg),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary.withValues(alpha: 0.16),
          selectedForegroundColor: scheme.primary,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(
            fontFamily: MeshFonts.sans,
            fontFamilyFallback: MeshFonts.sansFallback,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        valueIndicatorColor: scheme.surfaceContainerHighest,
        valueIndicatorTextStyle: TextStyle(
          fontFamily: MeshFonts.mono,
          fontFamilyFallback: MeshFonts.monoFallback,
          color: scheme.onSurface,
          fontSize: 12,
        ),
        trackHeight: 3,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
        labelStyle: const TextStyle(
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(MeshRadii.sm),
          border: Border.all(color: scheme.outline),
        ),
        textStyle: TextStyle(color: scheme.onSurface, fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeshRadii.pill),
          ),
          textStyle: const TextStyle(
            fontFamily: MeshFonts.sans,
            fontFamilyFallback: MeshFonts.sansFallback,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  /// Mono text style — sizes default to the body size Inter is using.
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: MeshFonts.mono,
      fontFamilyFallback: MeshFonts.monoFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing ?? 0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Serif display style.
  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: MeshFonts.display,
      fontFamilyFallback: MeshFonts.displayFallback,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w400,
      color: color,
      letterSpacing: letterSpacing ?? -0.2,
    );
  }

  /// Section-accent / chip label — sans for legibility, with light tracking
  /// to keep the "label" feel that section headers rely on.
  static TextStyle accentLabel({Color? color, double? fontSize}) {
    return TextStyle(
      fontFamily: MeshFonts.sans,
      fontFamilyFallback: MeshFonts.sansFallback,
      fontSize: fontSize ?? 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: color,
    );
  }

  /// Color-emoji style with platform fallbacks and stable vertical metrics.
  static TextStyle emoji({double fontSize = 28}) {
    return TextStyle(
      fontFamily: MeshFonts.emoji,
      fontFamilyFallback: MeshFonts.emojiFallback,
      fontSize: fontSize,
      height: 1,
    );
  }

  /// Color-code an SNR value for consistency across the app.
  /// Signal-quality ramp.
  ///
  /// Pass [scheme] wherever the result is painted on an ordinary surface so the
  /// dark-tuned greens and ambers are resolved for the current brightness;
  /// omitting it keeps the raw palette value for map overlays and other
  /// deliberately dark contexts.
  static Color snrColor(
    num? snr, {
    required bool blocked,
    ColorScheme? scheme,
  }) {
    final raw = _rawSnrColor(snr, blocked: blocked, scheme: scheme);
    return scheme == null ? raw : readableOn(raw, scheme.surface);
  }

  static Color _rawSnrColor(
    num? snr, {
    required bool blocked,
    ColorScheme? scheme,
  }) {
    if (blocked) return MeshPalette.alert;
    // "Unknown" is chrome rather than signal, so it follows the scheme's muted
    // ink instead of the dark palette's (1.4:1 on a light surface).
    if (snr == null) return scheme?.onSurfaceVariant ?? MeshPalette.ink3;
    if (snr > -5) return MeshPalette.signal;
    if (snr > -12) return MeshPalette.warn;
    return MeshPalette.alert;
  }
}
