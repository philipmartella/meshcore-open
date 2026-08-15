import 'package:flutter/material.dart';

import '../theme/mesh_theme.dart';

class UnreadBadge extends StatelessWidget {
  final int count;

  const UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    // A solid attention badge: the scheme's error pair is exactly this
    // semantic and is contrast-checked in both themes, where the raw palette
    // red with white text was 3.8:1.
    final scheme = Theme.of(context).colorScheme;
    final display = count > 9999 ? '9999+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(MeshRadii.pill),
      ),
      child: Text(
        display,
        style: MeshTheme.mono(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onError,
        ),
      ),
    );
  }
}
