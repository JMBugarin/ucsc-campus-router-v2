import 'dart:math' as math;

import '../location/location_service.dart';

/// The area the server's walking graph covers (`graph/ucsc/meta.json`), and the same margin the
/// server allows around it. A phone inside it is "on campus"; its location never needs to leave the phone
/// to decide that.
const campusWest = -122.07;
const campusSouth = 36.986;
const campusEast = -122.046;
const campusNorth = 37.003;
const campusMarginDegrees = 0.002;

const campusCenter = GeoPoint(36.9945, -122.058);

/// Beyond this distance from campus there is no sensible bus trip to plan.
const farFromCampusKm = 60.0;

enum Whereabouts { onCampus, offCampus, far }

bool isOnCampus(GeoPoint p) =>
    p.lat >= campusSouth - campusMarginDegrees &&
    p.lat <= campusNorth + campusMarginDegrees &&
    p.lon >= campusWest - campusMarginDegrees &&
    p.lon <= campusEast + campusMarginDegrees;

Whereabouts whereIs(GeoPoint p) {
  if (isOnCampus(p)) return Whereabouts.onCampus;
  return distanceKm(p, campusCenter) > farFromCampusKm
      ? Whereabouts.far
      : Whereabouts.offCampus;
}

double distanceKm(GeoPoint a, GeoPoint b) {
  double rad(double d) => d * math.pi / 180;
  final h =
      math.pow(math.sin(rad(b.lat - a.lat) / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(rad(b.lon - a.lon) / 2), 2);
  return 2 * 6371.0088 * math.asin(math.sqrt(h.clamp(0.0, 1.0).toDouble()));
}
