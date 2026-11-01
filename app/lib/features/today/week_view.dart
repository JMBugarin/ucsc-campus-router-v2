import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../campus/campus_data.dart';
import '../../campus/terms.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/pacific.dart';
import '../schedule/meeting.dart';
import '../schedule/schedule_controller.dart';
import 'day_plan.dart';
import 'today_controller.dart';

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
    week.add(
      WeekDay(
        day: day,
        classes: classes,
        reason: classes.isEmpty ? whyNoClasses(meetings, day, holidays) : null,
      ),
    );
  }
  return week;
}

/// The first and last day the schedule covers, widened to include [today], as midnight UTC.
({DateTime first, DateTime last}) scheduleSpan(
  List<Meeting> meetings,
  DateTime today,
) {
  var first = today, last = today;
  for (final m in meetings) {
    final s = DateTime.tryParse('${m.startDate}T00:00:00Z'),
        e = DateTime.tryParse('${m.endDate}T00:00:00Z');
    if (s != null && s.isBefore(first)) first = s;
    if (e != null && e.isAfter(last)) last = e;
  }
  return (first: first, last: last);
}

/// `3 classes, 9:00 AM to 3:45 PM.`, or why there are none.
String weekDayText(WeekDay d) {
  if (d.classes.isEmpty) return noClassesOnOtherDayText(d.reason);
  final first = d.classes.first.start, last = d.classes.last.end;
  return classCountText(
    d.classes.length,
    clock12(first.hour, first.minute),
    clock12(last.hour, last.minute),
  );
}

/// A week at a glance, from the schedule saved on the phone.
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
    final today = DateTime.utc(
      nowPacific.year,
      nowPacific.month,
      nowPacific.day,
    );
    final viewed = ref.watch(viewedDayProvider);
    final start = _start ?? today;
    final span = scheduleSpan(meetings, today);
    final holidays = holidaysOf(ref.watch(termsProvider).value ?? const []);
    final week = weekFrom(meetings: meetings, start: start, holidays: holidays);
    DateTime weeks(int n) =>
        DateTime.utc(start.year, start.month, start.day + 7 * n);
    final end = week.last.day;

    return Scaffold(
      appBar: AppBar(title: const Text('Week')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous week',
                icon: const Icon(Icons.chevron_left),
                onPressed: start.isAfter(span.first)
                    ? () => setState(() => _start = weeks(-1))
                    : null,
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
                onPressed: end.isBefore(span.last)
                    ? () => setState(() => _start = weeks(1))
                    : null,
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
  const _WeekRow({
    required this.day,
    required this.isToday,
    required this.isShown,
    required this.onTap,
  });

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
          color: isShown
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isShown ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        selected: isShown,
        title: Text(
          isToday ? 'Today, ${dayLabel(day.day)}' : dayLabel(day.day),
        ),
        subtitle: Text(weekDayText(day)),
        textColor: quiet ? theme.colorScheme.onSurfaceVariant : null,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
