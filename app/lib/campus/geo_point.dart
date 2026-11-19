import 'dart:math' as math;

const _compass = [
  'north',
  'north-east',
  'east',
  'south-east',
  'south',
  'south-west',
  'west',
  'north-west',
];

class GeoPoint {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  static double _rad(double d) => d * math.pi / 180;

  /// Great-circle distance in metres.
  double metresTo(GeoPoint o) {
    final dLat = _rad(o.lat - lat);
    final dLon = _rad(o.lon - lon);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat)) *
            math.cos(_rad(o.lat)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * 6371000 * math.asin(math.sqrt(h));
  }

  /// Eight-point compass direction from here to [o], such as `south-west`.
  String compassTo(GeoPoint o) {
    final dLon = _rad(o.lon - lon);
    final y = math.sin(dLon) * math.cos(_rad(o.lat));
    final x =
        math.cos(_rad(lat)) * math.sin(_rad(o.lat)) -
        math.sin(_rad(lat)) * math.cos(_rad(o.lat)) * math.cos(dLon);
    final deg = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    return _compass[(deg / 45).round() % 8];
  }

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => '$lat,$lon';
}
