import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class GeoPoint {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => '$lat,$lon';
}

/// Either where the phone is, or a plain-language reason it could not be found out.
class LocationResult {
  const LocationResult.found(GeoPoint this.point) : problem = null;
  const LocationResult.unavailable(String this.problem) : point = null;

  final GeoPoint? point;
  final String? problem;
}

abstract class LocationService {
  Future<LocationResult> current();
}

/// Uses the phone's GPS, asking for permission the first time.
class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.unavailable('Location is turned off on this phone.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.unavailable('Location permission was not given.');
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.unavailable(
          'Location is blocked for this app. Allow it in the phone\'s app settings.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationResult.found(GeoPoint(position.latitude, position.longitude));
    } on Exception {
      return const LocationResult.unavailable("Couldn't get your location. Try again outdoors.");
    }
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => GeolocatorLocationService());
