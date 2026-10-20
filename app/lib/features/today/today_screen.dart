import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/pacific.dart';
import '../../core/waking_note.dart';
import '../route/destination.dart';
import '../route/route_screen.dart';
import '../schedule/schedule_controller.dart';
import '../settings/settings.dart';
import 'today_controller.dart';
import 'today_models.dart';
import 'today_text.dart';
import 'walk_cache.dart';
import 'week_view.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(settingsProvider.select((s) => s.serverUrl));
    final today = ref.watch(todayProvider);
    final meetings = ref.watch(scheduleProvider).value ?? const [];
    final otherDay = ref.watch(viewedDayProvider) != null;

    Future<void> refresh() => ref.read(todayProvider.notifier).refresh();

    // While the server answers (it may be waking up) show what the phone already knows, if anything.
    Widget loading() {
      final saved = otherDay
          ? null
          : savedToday(meetings: meetings, walks: ref.read(walkCacheProvider), now: ref.read(clockProvider)());
      return saved == null ? const _LoadingCard() : _TodayBody(data: saved);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            tooltip: 'Week',
            icon: const Icon(Icons.calendar_view_week_outlined),
            onPressed: meetings.isEmpty
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeekScreen())),
          ),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: serverUrl.isEmpty ? null : refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (serverUrl.isEmpty)
              _MessageCard(
                icon: Icons.cloud_off_outlined,
                title: 'Connect to the server',
                body: 'The app needs the address of the campus router server to work out your walks.',
                actionLabel: 'Open Settings',
                onAction: () => ref.read(selectedTabProvider.notifier).select(tabSettings),
              )
            else
              today.when(
                loading: loading,
                error: (error, _) => _MessageCard(
                  icon: Icons.error_outline,
                  title: "Couldn't work out your day",
                  body: error is ApiException ? error.message : 'Something went wrong. Try again.',
                  actionLabel: 'Try again',
                  onAction: refresh,
                ),
                data: (data) => _TodayBody(data: data),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.data});

  final TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = data.analysis;
    if (analysis == null) {
      return _MessageCard(
        icon: Icons.calendar_month_outlined,
        title: 'Add your classes',
        body: 'Paste your MyUCSC schedule, import a calendar file, or add classes by hand. Then this '
            'screen shows what is next, how long the walk is, and whether you have time.',
        actionLabel: 'Go to Schedule',
        onAction: () => ref.read(selectedTabProvider.notifier).select(tabSchedule),
      );
    }

    final walk = walkText(analysis, saved: data.fromSaved);
    final viewing = data.viewDay != null;
    final notes = [
      if (data.locationProblem != null) data.locationProblem!,
      if (data.reminderProblem != null) data.reminderProblem!,
      if (!viewing) ...analysis.notes, // another day has no "next class" to walk to, so no walk to explain
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.fromSaved) _SavedBanner(data: data),
        _DayBar(viewDay: data.viewDay),
        Text(viewing ? dayViewSummary(analysis) : todaySummary(analysis), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (analysis.banner != null) _Banner(banner: analysis.banner!),
        if (walk != null && !viewing)
          _WalkCard(
            status: walk.status,
            text: walk.text,
            onRoute: analysis.next == null
                ? null
                : () => openRoute(context, destination: RoomDestination(analysis.next!.location)),
          ),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(note, style: Theme.of(context).textTheme.bodyMedium),
          ),
        if (analysis.today.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(viewing ? 'Classes on ${dayLabel(data.viewDay!)}' : "Today's classes", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final t in analysis.today) _TimelineTile(classTime: t, analysis: viewing ? null : analysis),
        ],
      ],
    );
  }
}

/// Says plainly that what is on screen comes from the phone's memory: the server could not be
/// reached, or has not answered yet.
class _SavedBanner extends ConsumerWidget {
  const _SavedBanner({required this.data});

  final TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    final offline = data.offline;
    final lead = offline
        ? "Can't reach the server, so this is worked out on your phone."
        : 'Showing what is saved on this phone while the server answers.';
    return Semantics(
      liveRegion: true,
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(offline ? Icons.cloud_off_outlined : Icons.sync, color: color),
                  const SizedBox(width: 8),
                  Text(offline ? 'Offline' : 'Updating…', style: theme.textTheme.titleSmall?.copyWith(color: color)),
                ],
              ),
              const SizedBox(height: 6),
              Text('$lead ${data.savedNote ?? ''}'.trim(), style: theme.textTheme.bodyMedium?.copyWith(color: color)),
              if (offline)
                TextButton(
                  onPressed: () => ref.read(todayProvider.notifier).refresh(),
                  child: const Text('Try again'),
                )
              else ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                const WakingNote(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Steps through the days of the schedule; a tap on the date opens a calendar.
class _DayBar extends ConsumerWidget {
  const _DayBar({required this.viewDay});

  final DateTime? viewDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(scheduleProvider).value ?? const [];
    final nowPacific = pacificTime(ref.read(clockProvider)());
    final today = DateTime.utc(nowPacific.year, nowPacific.month, nowPacific.day);
    final shown = viewDay ?? today;
    final (:first, :last) = scheduleSpan(meetings, today);
    final controller = ref.read(viewedDayProvider.notifier);
    DateTime step(int days) => DateTime.utc(shown.year, shown.month, shown.day + days);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: shown.isAfter(first) ? () => controller.show(step(-1)) : null,
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
              child: Text(viewDay == null ? 'Today, ${dayLabel(today)}' : dayLabel(shown)),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: shown.isBefore(last) ? () => controller.show(step(1)) : null,
          ),
          if (viewDay != null) TextButton(onPressed: controller.backToToday, child: const Text('Today')),
        ],
      ),
    );
  }
}

/// A status chip that never relies on colour alone: it always carries a word.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ok' => ('OK', Colors.green.shade700),
      'tight' => ('Tight', Colors.orange.shade800),
      'late' => ('Late', Colors.red.shade700),
      _ => ('?', Colors.grey.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class _WalkCard extends StatelessWidget {
  const _WalkCard({required this.status, required this.text, this.onRoute});

  final String status;
  final String text;
  final VoidCallback? onRoute;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusChip(status: status),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text),
                  if (onRoute != null)
                    TextButton.icon(
                      onPressed: onRoute,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Show route'),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.banner});

  final LeaveBanner banner;

  @override
  Widget build(BuildContext context) {
    final color = banner.late ? Colors.red.shade700 : Colors.orange.shade800;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            const Icon(Icons.directions_walk, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(banner.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.classTime, required this.analysis});

  final ClassTime classTime;

  /// Null when another day is shown, where nothing is "now" or "next".
  final Analysis? analysis;

  @override
  Widget build(BuildContext context) {
    final isNow = analysis?.current?.start == classTime.start;
    final isNext = analysis?.next?.isToday == true && analysis?.next?.start == classTime.start;
    final scheme = Theme.of(context).colorScheme;
    final transition = transitionText(classTime);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isNow ? scheme.primary : (isNext ? scheme.tertiary : scheme.outlineVariant),
          width: isNow || isNext ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (transition != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusChip(status: transition.status),
                    const SizedBox(width: 8),
                    Expanded(child: Text(transition.text, style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
            Text(
              '${clockFromIso(classTime.start)}–${clockFromIso(classTime.end)}'
              '${isNow ? '  ·  now' : (isNext ? '  ·  next' : '')}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 2),
            Text(classTime.label, style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                Expanded(child: Text(classTime.location)),
                if (classTime.location.isNotEmpty)
                  IconButton(
                    tooltip: 'Route to ${classTime.label}',
                    icon: const Icon(Icons.map_outlined),
                    onPressed: () => openRoute(context, destination: RoomDestination(classTime.location)),
                  ),
              ],
            ),
          ],
        ),
      ),
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
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body),
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 12),
            Text('Working out your day…'),
            WakingNote(),
          ],
        ),
      ),
    );
  }
}
