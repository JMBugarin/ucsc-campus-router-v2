import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../campus/campus.dart';
import '../../campus/geo_point.dart';
import '../../design/floating_bar.dart';

/// Where to send someone who wants to walk to a room: the point on the map and what to call it.
class WalkTarget {
  const WalkTarget({required this.label, required this.point});

  final String label;
  final GeoPoint point;
}

/// The door to walk to for [location] (a schedule-style place such as `Kresge Acad 3201`), or null when it
/// is online, to be announced, unknown, or has no position yet. A door the data pins for the room comes first,
/// then the building's main entrance, then any entrance, then the room itself, then the building's middle.
WalkTarget? walkTarget(Campus campus, String location) {
  final r = campus.resolve(location);
  if (r.kind != 'building') return null;
  final building = campus.buildings[r.buildingId]!;
  Entrance? door;
  for (final kind in const ['override', 'main']) {
    door ??= r.entrances.where((e) => e.kind == kind).firstOrNull;
  }
  door ??= r.entrances.firstOrNull;
  final point = door?.point ?? r.roomPoint?.point ?? building.centroid;
  if (point == null) return null;
  return WalkTarget(
    label: r.room == null ? building.name : '${building.name} ${r.room}',
    point: point,
  );
}

/// A link that opens walking directions to [target] in the phone's maps app, starting from where the phone is.
/// Apple Maps on iPhones, Google Maps elsewhere. The app never learns where the phone is.
Uri walkingDirectionsUri(WalkTarget target, {required bool android}) {
  final destination = '${target.point.lat},${target.point.lon}';
  return android
      ? Uri.https('www.google.com', '/maps/dir/', {
          'api': '1',
          'destination': destination,
          'travelmode': 'walking',
        })
      : Uri.https('maps.apple.com', '/', {'daddr': destination, 'dirflg': 'w'});
}

/// Opens a link outside the app. Tests replace it.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Opens walking directions to [target] in the maps app, or says why it could not.
Future<void> walkThere(
  BuildContext context,
  WidgetRef ref,
  WalkTarget target,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final inset = FloatingBarInset.of(context);
  final uri = walkingDirectionsUri(
    target,
    android: defaultTargetPlatform == TargetPlatform.android,
  );
  var opened = false;
  try {
    opened = await ref.read(urlOpenerProvider)(uri);
  } on Object {
    opened = false;
  }
  if (!opened) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        floatingSnackBar(
          inset: inset,
          content: const Text("Couldn't open your maps app."),
        ),
      );
  }
}
