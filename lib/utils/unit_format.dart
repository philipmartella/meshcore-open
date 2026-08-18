import '../models/app_settings.dart';

/// Distance and duration formatting for the user's chosen unit system.
///
/// Values are always held in metres and seconds; conversion happens here, at
/// the point of display.
class UnitFormat {
  UnitFormat._();

  static const double _metresPerMile = 1609.344;
  static const double _metresPerFoot = 0.3048;

  static bool isImperial(UnitSystem system) => system == UnitSystem.imperial;

  /// Distance for display: switches to the small unit under roughly a tenth of
  /// the large one, so "0.06 mi" reads as "320 ft" instead.
  static String distance(double metres, {required bool imperial}) {
    if (imperial) {
      final miles = metres / _metresPerMile;
      if (miles < 0.1) {
        return '${(metres / _metresPerFoot).round()} ft';
      }
      return '${miles.toStringAsFixed(miles >= 100 ? 0 : 1)} mi';
    }
    if (metres < 1000) return '${metres.round()} m';
    final km = metres / 1000;
    return '${km.toStringAsFixed(km >= 100 ? 0 : 1)} km';
  }

  /// Compact duration: "45m", "1h 47m".
  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }
}
