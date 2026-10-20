import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../location/location_service.dart';

/// How the student gets to an entry point.
enum TravelMode { walking, cycling, driving, transit }

/// The Transit app's page in the App Store.
final transitStoreUri = Uri.parse('https://apps.apple.com/us/app/transit-app/id498151501');

/// A trip in the Transit app to [to]. `from` is left out on purpose: Transit's documentation says that
/// leaving out a parameter uses the user's current location, so the phone's position stays between
/// the student and Transit.
Uri transitUri(GeoPoint to) => Uri.parse('transit://directions?to=${to.lat},${to.lon}');

/// Directions to [to] in the phone's maps app, from wherever the student is: Apple Maps on iOS
/// (`/directions` with `destination` and `mode`, as Apple documents for iOS 18.4 and later) and Google
/// Maps elsewhere.
Uri mapsUri(GeoPoint to, TravelMode mode, {TargetPlatform? platform}) {
  if ((platform ?? defaultTargetPlatform) == TargetPlatform.iOS) {
    return Uri.parse('https://maps.apple.com/directions?destination=${to.lat},${to.lon}&mode=${mode.name}');
  }
  final travel = switch (mode) {
    TravelMode.cycling => 'bicycling',
    _ => mode.name,
  };
  return Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${to.lat},${to.lon}&travelmode=$travel');
}

String mapsAppName({TargetPlatform? platform}) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.iOS ? 'Apple Maps' : 'Google Maps';

/// Opens links in other apps. The real one uses the system; tests use a fake.
abstract class LinkLauncher {
  Future<bool> canOpen(Uri uri);
  Future<bool> open(Uri uri);
}

class SystemLinkLauncher implements LinkLauncher {
  @override
  Future<bool> canOpen(Uri uri) async {
    try {
      return await canLaunchUrl(uri);
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

final linkLauncherProvider = Provider<LinkLauncher>((ref) => SystemLinkLauncher());

enum HandoffResult {
  /// Transit opened with the trip.
  transit,

  /// Transit is not installed, so the phone's maps app opened with transit directions instead.
  mapsInstead,

  /// Nothing could be opened.
  failed,
}

/// Opens a trip to [to] in Transit, or in the phone's maps app when Transit is not installed.
Future<HandoffResult> openTransit(LinkLauncher launcher, GeoPoint to, {TargetPlatform? platform}) async {
  final uri = transitUri(to);
  if (await launcher.canOpen(uri)) {
    return await launcher.open(uri) ? HandoffResult.transit : HandoffResult.failed;
  }
  return await launcher.open(mapsUri(to, TravelMode.transit, platform: platform))
      ? HandoffResult.mapsInstead
      : HandoffResult.failed;
}

/// What to tell the student after [openTransit]; null when Transit simply opened.
String? handoffMessage(HandoffResult result, {TargetPlatform? platform}) => switch (result) {
      HandoffResult.transit => null,
      HandoffResult.mapsInstead =>
        "Transit isn't installed, so this opened in ${mapsAppName(platform: platform)}.",
      HandoffResult.failed => "Couldn't open Transit or ${mapsAppName(platform: platform)}. Check that one of them is installed.",
    };
