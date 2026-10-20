import 'package:timezone/timezone.dart' as tz;

import '../../core/format.dart';
import '../../core/pacific.dart';
import '../campus/campus_area.dart';
import '../location/location_service.dart';
import '../today/today_models.dart';
import 'entry_walks.dart';

/// Spare minutes added to the campus walk for a student who is not on campus yet: buses and parking
/// run late in ways a walk across campus does not.
const offCampusBufferMinutes = 10;

/// Off-campus reminders cannot know how long the trip to campus takes, so the first comes this long
/// before the time to be at the entry point and the second shortly before it.
const tripHeadsUpMinutes = 30;
const tripLeaveMinutes = 10;

/// When a student who is off campus has to be at an entry point to reach a class on time.
class Arrival {
  const Arrival({
    required this.classTime,
    required this.walk,
    required this.options,
    required this.arriveBy,
    required this.bufferMinutes,
  });

  final ClassTime classTime;

  /// The entry point to be at, with its walk to the room.
  final EntryWalk walk;

  /// Every entry point, in the order to offer them (the best guess first).
  final List<EntryWalk> options;
  final tz.TZDateTime arriveBy;
  final int bufferMinutes;

  EntryPoint get entry => walk.entry;
  int get walkMinutes => walk.minutes;

  String get arriveByClock => clock12(arriveBy.hour, arriveBy.minute);

  String get headline => 'Be at ${entry.name} by $arriveByClock';
}

/// Entry points whose walk to the room is this much longer than the shortest are offered after the others,
/// however close to the student they are: a stop next door with a half-hour walk to class is no help.
const reasonableExtraWalkMinutes = 10;

/// The entry points to offer: nearest to [here] first among those with a reasonable walk, then the rest.
/// With no location they run shortest walk first.
List<EntryWalk> orderEntries(List<EntryWalk> walks, GeoPoint? here) {
  if (walks.isEmpty) return [];
  if (here == null) return [...walks]..sort((a, b) => a.minutes.compareTo(b.minutes));
  final shortest = walks.map((w) => w.minutes).reduce((a, b) => a < b ? a : b);
  final far = {for (final w in walks) w.entry.id: distanceKm(here, w.entry.point)};
  int byDistance(EntryWalk a, EntryWalk b) => far[a.entry.id]!.compareTo(far[b.entry.id]!);
  bool reasonable(EntryWalk w) => w.minutes <= shortest + reasonableExtraWalkMinutes;
  return [
    ...walks.where(reasonable).toList()..sort(byDistance),
    ...walks.where((w) => !reasonable(w)).toList()..sort(byDistance),
  ];
}

/// The student's remembered choice if it is still on offer, otherwise the first entry point.
EntryWalk chooseEntry(List<EntryWalk> ordered, String? chosenId) => ordered
    .firstWhere((w) => w.entry.id == chosenId, orElse: () => ordered.first);

Arrival planArrival({
  required ClassTime classTime,
  required EntryWalks walks,
  GeoPoint? here,
  String? chosenId,
  int bufferMinutes = offCampusBufferMinutes,
}) {
  final options = orderEntries(walks.walks, here);
  final walk = chooseEntry(options, chosenId);
  final start = pacificTime(DateTime.parse(classTime.start));
  return Arrival(
    classTime: classTime,
    walk: walk,
    options: options,
    arriveBy: start.subtract(Duration(minutes: walk.minutes + bufferMinutes)),
    bufferMinutes: bufferMinutes,
  );
}

/// The same plan with another entry point picked.
Arrival withEntry(Arrival arrival, EntryWalk walk) {
  final start = pacificTime(DateTime.parse(arrival.classTime.start));
  return Arrival(
    classTime: arrival.classTime,
    walk: walk,
    options: arrival.options,
    arriveBy: start.subtract(
      Duration(minutes: walk.minutes + arrival.bufferMinutes),
    ),
    bufferMinutes: arrival.bufferMinutes,
  );
}

/// Notifications for the classes still to come, keyed like the server's (`<class start>|<stage>`) so a
/// reminder is never shown twice. Keys in [sent] are skipped. [leadMinutes] of 0 turns the early one off.
List<Reminder> arrivalReminders(
  List<Arrival> arrivals,
  DateTime now, {
  Set<String> sent = const {},
  int leadMinutes = 5,
}) {
  final plan = <Reminder>[];
  for (final a in arrivals) {
    final body =
        '${a.classTime.location}: about ${a.walkMinutes} min on foot from there. '
        'Class starts at ${clockFromIso(a.classTime.start)}.';
    final name = a.classTime.label;

    void add(String stage, Duration before, String title) {
      final key = '${a.classTime.start}|$stage';
      final seconds =
          a.arriveBy.subtract(before).difference(now).inMilliseconds / 1000;
      if (seconds >= 0 && !sent.contains(key)) {
        plan.add(
          Reminder(
            stage: stage,
            key: key,
            inSeconds: seconds,
            title: title,
            body: body,
          ),
        );
      }
    }

    if (leadMinutes > 0) {
      add(
        'heads-up',
        const Duration(minutes: tripHeadsUpMinutes),
        'Head to campus for $name: ${a.headline}',
      );
    }
    add('leave', const Duration(minutes: tripLeaveMinutes), a.headline);
  }
  plan.sort((x, y) => x.inSeconds.compareTo(y.inSeconds));
  return plan;
}
