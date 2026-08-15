import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../theme/mesh_theme.dart';

class BatteryUi {
  final IconData icon;
  final Color? color;
  const BatteryUi(this.icon, this.color);
}

/// Icon + color for a battery level.
///
/// Pass [scheme] when the icon is drawn on an ordinary surface: the alert red,
/// amber and green here were picked against the dark surface and wash out on
/// the light one. Omitting it returns the raw palette value, which is what map
/// overlays and other deliberately dark contexts want.
BatteryUi batteryUiForPercent(int? percent, {ColorScheme? scheme}) {
  if (percent == null) {
    return const BatteryUi(Icons.battery_unknown, null);
  }

  final p = percent.clamp(0, 100);

  final ui = switch (p) {
    <= 5 => const BatteryUi(Icons.battery_alert, MeshPalette.alert),
    <= 15 => const BatteryUi(Icons.battery_0_bar, MeshPalette.alert),
    <= 30 => const BatteryUi(Icons.battery_1_bar, MeshPalette.warn),
    <= 45 => const BatteryUi(Icons.battery_2_bar, MeshPalette.warn),
    <= 60 => const BatteryUi(Icons.battery_3_bar, null),
    <= 80 => const BatteryUi(Icons.battery_5_bar, null),
    _ => const BatteryUi(Icons.battery_full, MeshPalette.signal),
  };
  final color = ui.color;
  if (scheme == null || color == null) return ui;
  return BatteryUi(ui.icon, MeshTheme.readableOn(color, scheme.surface));
}

class BatteryIndicator extends StatefulWidget {
  final MeshCoreConnector connector;

  const BatteryIndicator({super.key, required this.connector});

  @override
  State<BatteryIndicator> createState() => _BatteryIndicatorState();
}

class _BatteryIndicatorState extends State<BatteryIndicator> {
  bool _showBatteryVoltage = false;

  @override
  Widget build(BuildContext context) {
    final percent = widget.connector.batteryPercent;
    final millivolts = widget.connector.batteryMillivolts;

    if (millivolts == null) {
      return const SizedBox.shrink();
    }

    final String displayText;
    if (_showBatteryVoltage) {
      displayText = '${(millivolts / 1000.0).toStringAsFixed(2)}V';
    } else {
      displayText = percent != null ? '$percent%' : '—';
    }

    final batteryUi = batteryUiForPercent(
      percent,
      scheme: Theme.of(context).colorScheme,
    );

    return InkWell(
      onTap: () {
        setState(() {
          _showBatteryVoltage = !_showBatteryVoltage;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(batteryUi.icon, size: 18, color: batteryUi.color),
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    displayText,
                    style: MeshTheme.mono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: batteryUi.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
