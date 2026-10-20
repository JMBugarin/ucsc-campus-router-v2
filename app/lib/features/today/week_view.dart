import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/pacific.dart';
import '../schedule/meeting.dart';
import '../schedule/schedule_controller.dart';
import 'offline_analysis.dart';
import 'today_controller.dart';
import 'today_text.dart';
import 'walk_cache.dart';

/// One day of the week view: its classes in time order, or why there are none.
class WeekDay {
  const WeekDay({required this.day, required this.classes, this.reason});

  /// The calendar date, as midnight UTC.
  final DateTime day;
  final List<Occurrence> classes;

  /// `weekend`, `holiday`, ... when there are no classes (see [whyNoClasses]).
  final String? reason;
}

/// [days] days from [start] with their classes, worked out on the phone from the saved schedule.
List<WeekDay> weekFrom({
  required List<Meeting> meetings,
  required DateTime start,
  required Set<String> holidays,
  int days = 7,
}) {
  final week = <WeekDay>[];
  for (var i = 0; i < days; i++) {
    final day = DateTime.utc(start.year, start.month, start.day + i);
    final classes = occurrences(meetings, day, holidays);
    week.add(WeekDay(day: day, classes: classes, reason: classes.isEmpty ? whyNoClasses(meetings, day, holidays) : null));
  }
  return week;
}

/// The first and last day the schedule covers, widened to include [today], as midnight UTC.
({DateTime first, DateTime last}) scheduleSpan(List<Meeting> meetings, DateTime today) {
  var first = today, last = today;
  for (final m in meetings) {
    final s = DateTime.tryParse('${m.startDate}T00:00:00Z'), e = DateTime.tryParse('${m.endDate}T00:00:00Z');
    if (s != null && s.isBefore(first)) first = s;
    if (e != null && e.isAfter(last)) last = e;
  }
  return (first: first, last: last);
}

/// `3 classes, 9:00 AM to 3:45 PM.`, or why there are none.
String weekDayText(WeekDay d) {
  if (d.classes.isEmpty) return noClassesOnOtherDayText(d.reason);
  final first = d.classes.first.start, last = d.classes.last.end;
  return classCountText(d.classes.length, clock12(first.hour, first.minute), clock12(last.hour, last.minute));
}

/// A week at a glance, from the schedule saved on the phone, so it works with no connection at all.
/// Tapping a day opens it in Today.
class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key});

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  DateTime? _start;

  @override
  Widget build(BuildContext context) {
    final meetings = ref.watch(scheduleProvider).value ?? const <Meeting>[];
    final nowPacific = pacificTime(ref.read(clockProvider)());
    final today = DateTime.utc(nowPacific.year, nowPacific.month, nowPacific.day);
    final viewed = ref.watch(viewedDayProvider);
    final start = _start ?? today;
    final span = scheduleSpan(meetings, today);
    final walks = ref.read(walkCacheProvider);
    final week = weekFrom(meetings: meetings, start: start, holidays: walks.holidays);
    final offline = ref.watch(todayProvider.select((t) => t.value?.offline ?? false));
    DateTime weeks(int n) => DateTime.utc(start.year, start.month, start.day + 7 * n);
    final end = week.last.day;

    return Scaffold(
      appBar: AppBar(title: const Text('Week')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (offline) _OfflineNote(walks: walks, now: ref.read(clockProvider)()),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous week',
                icon: const Icon(Icons.chevron_left),
                onPressed: start.isAfter(span.first) ? () => setState(() => _start = weeks(-1)) : null,
              ),
              Expanded(
                child: Text(
                  '${dayLabel(start)} to ${dayLabel(end)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Next week',
                icon: const Icon(Icons.chevron_right),
                onPressed: end.isBefore(span.last) ? () => setState(() => _start = weeks(1)) : null,
              ),
            ],
          ),
          for (final d in week)
            _WeekRow(
              day: d,
              isToday: d.day == today,
              isShown: d.day == (viewed ?? today),
              onTap: () {
                ref.read(viewedDayProvider.notifier).show(d.day);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.day, required this.isToday, required this.isShown, required this.onTap});

  final WeekDay day;
  final bool isToday;
  final bool isShown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = day.classes.isEmpty;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isShown ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
          width: isShown ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        selected: isShown,
        title: Text(isToday ? 'Today, ${dayLabel(day.day)}' : dayLabel(day.day)),
        subtitle: Text(weekDayText(day)),
        textColor: quiet ? theme.colorScheme.onSurfaceVariant : null,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// What the week can and cannot say with no connection: the classes are the phone's own, but the
/// no-class days (holidays) are whatever the server last said.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote({required this.walks, required this.now});

  final WalkCache walks;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    final saved = walks.savedAt;
    final holidays = walks.holidays.isEmpty
        ? 'No-class days are not saved yet, so holidays are not marked.'
        : saved == null
            ? 'No-class days are from an earlier visit.'
            : 'No-class days were last updated ${agoText(now.difference(saved))}.';
    return Semantics(
      liveRegion: true,
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_off_outlined, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Offline. Classes come from your saved schedule. $holidays',
                  style: theme.textTheme.bodyMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
