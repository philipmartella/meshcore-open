import 'package:latlong2/latlong.dart';

/// Google encoded-polyline codec.
///
/// Valhalla emits shapes at **precision 6** (1e6), not the 1e5 the original
/// Google format and most examples use. Decoding at the wrong precision does
/// not fail — it yields coordinates off by a factor of ten, which lands the
/// route in the wrong hemisphere rather than throwing.
class PolylineCodec {
  PolylineCodec._();

  /// Valhalla's precision. Osrm and Google use 5.
  static const int valhallaPrecision = 6;

  static List<LatLng> decode(String encoded, {int precision = valhallaPrecision}) {
    final factor = _pow10(precision);
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      final dLat = _nextValue(encoded, index);
      index = dLat.nextIndex;
      lat += dLat.value;

      final dLng = _nextValue(encoded, index);
      index = dLng.nextIndex;
      lng += dLng.value;

      points.add(LatLng(lat / factor, lng / factor));
    }
    return points;
  }

  static String encode(
    List<LatLng> points, {
    int precision = valhallaPrecision,
  }) {
    final factor = _pow10(precision);
    final out = StringBuffer();
    var prevLat = 0;
    var prevLng = 0;
    for (final p in points) {
      final lat = (p.latitude * factor).round();
      final lng = (p.longitude * factor).round();
      _writeValue(out, lat - prevLat);
      _writeValue(out, lng - prevLng);
      prevLat = lat;
      prevLng = lng;
    }
    return out.toString();
  }

  static double _pow10(int n) {
    var v = 1.0;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }

  /// One zig-zag-encoded varint, five bits per character.
  static ({int value, int nextIndex}) _nextValue(String s, int start) {
    var result = 0;
    var shift = 0;
    var index = start;
    int chunk;
    do {
      if (index >= s.length) break;
      chunk = s.codeUnitAt(index++) - 63;
      result |= (chunk & 0x1f) << shift;
      shift += 5;
    } while (chunk >= 0x20);
    // Zig-zag: the low bit is the sign.
    final value = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    return (value: value, nextIndex: index);
  }

  static void _writeValue(StringBuffer out, int value) {
    var v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    out.writeCharCode(v + 63);
  }
}
