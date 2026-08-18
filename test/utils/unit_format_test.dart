import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/utils/unit_format.dart';

void main() {
  group('distance', () {
    test('metric switches to km at a kilometre', () {
      expect(UnitFormat.distance(20, imperial: false), '20 m');
      expect(UnitFormat.distance(999, imperial: false), '999 m');
      expect(UnitFormat.distance(1000, imperial: false), '1.0 km');
      expect(UnitFormat.distance(189900, imperial: false), '190 km');
    });

    test('imperial switches to feet below a tenth of a mile', () {
      // 0.06 mi reads better as 320 ft.
      expect(UnitFormat.distance(100, imperial: true), endsWith(' ft'));
      expect(UnitFormat.distance(100, imperial: true), '328 ft');
      expect(UnitFormat.distance(1609.344, imperial: true), '1.0 mi');
      expect(UnitFormat.distance(189900, imperial: true), '118 mi');
    });

    test('drops the decimal on large values', () {
      expect(UnitFormat.distance(50000, imperial: false), '50.0 km');
      expect(UnitFormat.distance(150000, imperial: false), '150 km');
    });

    test('the same distance reads differently per system', () {
      const m = 12900.0;
      expect(UnitFormat.distance(m, imperial: false), '12.9 km');
      expect(UnitFormat.distance(m, imperial: true), '8.0 mi');
    });
  });

  group('duration', () {
    test('formats compactly', () {
      expect(UnitFormat.duration(const Duration(minutes: 45)), '45m');
      expect(UnitFormat.duration(const Duration(minutes: 107)), '1h 47m');
      expect(UnitFormat.duration(const Duration(hours: 2)), '2h 0m');
    });
  });

  test('isImperial maps the setting', () {
    expect(UnitFormat.isImperial(UnitSystem.imperial), isTrue);
    expect(UnitFormat.isImperial(UnitSystem.metric), isFalse);
  });
}
