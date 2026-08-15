import 'package:flutter/material.dart';
import '../theme/mesh_theme.dart';

class SignalUi {
  final IconData icon;
  final Color color;

  const SignalUi({required this.icon, required this.color});
}

/// Icon + color for a signal-strength tier.
///
/// Pass [scheme] when the icon is drawn on an ordinary surface: the greens and
/// ambers here were picked against the dark surface and sit around 2:1 on the
/// light one. Omitting it returns the raw palette value, which is what map
/// overlays and other deliberately dark contexts want.
SignalUi signalUiForStrengthTier(int tier, {ColorScheme? scheme}) {
  final (icon, color) = switch (tier) {
    0 => (Icons.signal_cellular_4_bar, MeshPalette.signal),
    1 => (Icons.signal_cellular_alt, MeshPalette.signalDim),
    2 => (Icons.signal_cellular_alt_2_bar, MeshPalette.warn),
    3 => (Icons.signal_cellular_alt_1_bar, MeshPalette.warnDim),
    _ => (Icons.signal_cellular_alt_1_bar, MeshPalette.alert),
  };
  return SignalUi(
    icon: icon,
    color: scheme == null
        ? color
        : MeshTheme.readableOn(color, scheme.surface),
  );
}
