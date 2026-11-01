import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../campus/campus.dart';
import '../../campus/campus_data.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/pacific.dart';
import '../../design/controls.dart';
import '../../design/floating_bar.dart';
import '../../design/surfaces.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../directions/directions.dart';
import '../map/focused_place.dart';
import '../schedule/schedule_controller.dart';
import '../search/place.dart';
import 'day_plan.dart';
import 'today_controller.dart';
import 'week_view.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(dayPlanProvider);
    final meetings = ref.watch(scheduleProvider).value ?? const [];
    final inset = FloatingBarInset.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.xs,
                Space.md,
                Space.xxs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Today',
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                    ),
                  ),
                  GlassIconButton(
                    icon: Icons.calendar_view_week_outlined,
                    tooltip: 'Week',
                    onPressed: meetings.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const WeekScreen(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  Space.xs,
                  Space.md,
                  Space.md + inset,
                ),
                children: [
                  plan.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(Space.lg),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => _MessageCard(
                      icon: Icons.error_outline,
                      title: "Couldn't load your day",
                      body: 'Something went wrong reading your saved schedule.',
                      actionLabel: 'Try again',
                      onAction: () => ref.invalidate(scheduleProvider),
                    ),
                    data: (data) => _TodayBody(
                      plan: data,
                      hasSchedule: meetings.isNotEmpty,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.plan, required this.hasSchedule});

  final DayPlan plan;
  final bool hasSchedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasSchedule) {
      return _MessageCard(
        icon: Icons.calendar_month_outlined,
        title: 'Add your classes',
        body:
            'Paste your MyUCSC schedule, import a calendar file, or add classes by hand. Then this '
            'screen shows what is on today, where each room is, and a button to walk there. '
            'No schedule yet? You can still find any room on the map.',
        actionLabel: 'Go to Schedule',
        onAction: () =>
            ref.read(selectedTabProvider.notifier).select(tabSchedule),
        secondaryLabel: 'Find a room on the map',
        onSecondary: () =>
            ref.read(selectedTabProvider.notifier).select(tabMap),
      );
    }
    final now = ref.watch(nowProvider);
    final campus = ref.watch(campusProvider).value;
    final theme = Theme.of(context);
    final viewing = !plan.isToday;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DayBar(viewDay: viewing ? plan.day : null),
        Text(daySummary(plan, now), style: theme.textTheme.titleLarge),
        if (plan.classes.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text(
            viewing ? 'Classes on ${dayLabel(plan.day)}' : "Today's classes",
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Space.xs),
          for (final (i, occ) in plan.classes.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _ClassTile(
                occurrence: occ,
                role: viewing
                    ? ClassRole.later
                    : identical(plan.current, occ)
                    ? ClassRole.now
                    : (plan.next != null && identical(plan.next, occ)
                          ? ClassRole.next
                          : ClassRole.later),
                breakBefore: plan.breakBefore(i),
                campus: campus,
                canSkip: occ.end.isAfter(pacificTime(now)),
              ),
            ),
        ],
      ],
    );
  }
}

/// Steps through the days of the schedule; a tap on the date opens a calendar.
class _DayBar extends ConsumerWidget {
  const _DayBar({required this.viewDay});

  final DateTime? viewDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final meetings = ref.watch(scheduleProvider).value ?? const [];
    final nowPacific = pacificTime(ref.read(clockProvider)());
    final today = DateTime.utc(
      nowPacific.year,
      nowPacific.month,
      nowPacific.day,
    );
    final shown = viewDay ?? today;
    final (:first, :last) = scheduleSpan(meetings, today);
    final controller = ref.read(viewedDayProvider.notifier);
    DateTime step(int days) =>
        DateTime.utc(shown.year, shown.month, shown.day + days);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            color: c.accentText,
            icon: const Icon(Icons.chevron_left),
            onPressed: shown.isAfter(first)
                ? () => controller.show(step(-1))
                : null,
          ),
          Expanded(
            child: TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: shown,
                  firstDate: first,
                  lastDate: last,
                );
                if (picked != null) controller.show(picked);
              },
              child: Text(
                viewDay == null ? 'Today, ${dayLabel(today)}' : dayLabel(shown),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            color: c.accentText,
            icon: const Icon(Icons.chevron_right),
            onPressed: shown.isBefore(last)
                ? () => controller.show(step(1))
                : null,
          ),
          if (viewDay != null)
            TextButton(
              onPressed: controller.backToToday,
              child: const Text('Today'),
            ),
        ],
      ),
    );
  }
}

class _ClassTile extends ConsumerWidget {
  const _ClassTile({
    required this.occurrence,
    required this.role,
    required this.breakBefore,
    required this.campus,
    required this.canSkip,
  });

  final Occurrence occurrence;
  final ClassRole role;

  /// Minutes since the class before this one ended, or null for the first class.
  final double? breakBefore;
  final Campus? campus;
  final bool canSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final meeting = occurrence.meeting;
    final resolved = campus?.resolve(meeting.location);
    final building = resolved?.buildingId == null
        ? null
        : campus!.buildings[resolved!.buildingId]!.name;
    final target = campus == null
        ? null
        : walkTarget(campus!, meeting.location);
    final unknown = resolved?.kind == 'unknown';
    final room = [
      meeting.location,
      if (building != null && building != meeting.location) building,
    ].where((s) => s.isNotEmpty).join(' · ');
    return ClassCard(
      role: role,
      time:
          '${clock12(occurrence.start.hour, occurrence.start.minute)}–${clock12(occurrence.end.hour, occurrence.end.minute)}',
      title: occurrence.label,
      room: room,
      header: breakBefore == null
          ? null
          : Row(
              children: [
                Icon(Icons.schedule, size: 16, color: c.labelSecondary),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    breakBefore! < 0
                        ? 'Overlaps the class before'
                        : '${durationText(breakBefore!)} after your last class',
                    style: AppText.footnote.copyWith(color: c.labelSecondary),
                  ),
                ),
              ],
            ),
      flag: unknown ? "We can't find this room on the campus map." : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unknown)
            TextButton(
              onPressed: () =>
                  ref.read(selectedTabProvider.notifier).select(tabMap),
              child: const Text('Search the map'),
            )
          else if (campus != null &&
              placeFor(campus!, meeting.location) != null)
            IconButton(
              tooltip: 'Show ${occurrence.label} on the map',
              icon: const Icon(Icons.map_outlined),
              onPressed: () {
                ref
                    .read(focusedPlaceProvider.notifier)
                    .focus(placeFor(campus!, meeting.location)!);
                ref.read(selectedTabProvider.notifier).select(tabMap);
              },
            ),
          if (canSkip)
            PopupMenuButton<void>(
              tooltip: 'More for ${occurrence.label}',
              itemBuilder: (_) => [
                PopupMenuItem<void>(
                  onTap: () => skipClassDay(context, ref, occurrence),
                  child: const Text('Skip this day'),
                ),
              ],
            ),
        ],
      ),
      action: target != null && role != ClassRole.later
          ? FilledButton.icon(
              onPressed: () => walkThere(context, ref, target),
              icon: const Icon(Icons.directions_walk),
              label: const Text('Walk there'),
            )
          : null,
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: c.accentText),
            const SizedBox(height: Space.sm),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.xs),
            Text(
              body,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: c.labelSecondary,
              ),
            ),
            const SizedBox(height: Space.md),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (secondaryLabel != null && onSecondary != null)
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ),
      ),
    );
  }
}

/// Takes one class off one day, with an Undo.
Future<void> skipClassDay(
  BuildContext context,
  WidgetRef ref,
  Occurrence occurrence,
) async {
  final meeting = occurrence.meeting;
  final messenger = ScaffoldMessenger.of(
    context,
  ); // the tile itself is gone once the class is skipped
  final inset = FloatingBarInset.of(context);
  final day = isoDate(occurrence.start);
  final nowPacific = pacificTime(ref.read(clockProvider)());
  final schedule = ref.read(scheduleProvider.notifier);
  final skipped = await schedule.skipDay(
    meeting,
    day,
    today: isoDate(nowPacific),
  );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      floatingSnackBar(
        inset: inset,
        content: Text(
          skipped
              ? 'Skipped ${occurrence.label} on ${dayLabel(DateTime.parse(day))}.'
              : "Can't skip another day for ${occurrence.label}: too many days are already skipped.",
        ),
        action: skipped
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () => schedule.restoreDay(meeting, day),
              )
            : null,
      ),
    );
}
