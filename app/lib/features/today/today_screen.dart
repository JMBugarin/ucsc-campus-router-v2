import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/pacific.dart';
import '../../core/waking_note.dart';
import '../../design/controls.dart';
import '../../design/floating_bar.dart';
import '../../design/surfaces.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../arrive/arrival.dart';
import '../campus/campus_area.dart';
import '../going/going_to_class_screen.dart';
import '../handoff/trip_actions.dart';
import '../route/destination.dart';
import '../route/route_screen.dart';
import '../schedule/meeting.dart';
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
    final inset = FloatingBarInset.of(context);

    Future<void> refresh() => ref.read(todayProvider.notifier).refresh();

    // While the server answers (it may be waking up) show what the phone already knows, if anything.
    Widget loading() {
      final saved = otherDay
          ? null
          : savedToday(meetings: meetings, walks: ref.read(walkCacheProvider), now: ref.read(clockProvider)());
      return saved == null ? const _LoadingCard() : _TodayBody(data: saved);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.xxs),
              child: Row(
                children: [
                  Expanded(child: Semantics(header: true, child: Text('Today', style: Theme.of(context).textTheme.displayMedium))),
                  GlassIconButton(
                    icon: Icons.calendar_view_week_outlined,
                    tooltip: 'Week',
                    onPressed: meetings.isEmpty
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeekScreen())),
                  ),
                  const SizedBox(width: Space.sm),
                  GlassIconButton(icon: Icons.refresh, tooltip: 'Refresh', onPressed: serverUrl.isEmpty ? null : refresh),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.md + inset),
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
            'screen shows your next class, when to leave, and how to get there. '
            'No schedule yet? You can still find any room on the map.',
        actionLabel: 'Go to Schedule',
        onAction: () => ref.read(selectedTabProvider.notifier).select(tabSchedule),
        secondaryLabel: 'Find a room on the map',
        onSecondary: () => ref.read(selectedTabProvider.notifier).select(tabMap),
      );
    }

    final meetings = ref.watch(scheduleProvider).value ?? const [];
    final infos = ref.watch(locationInfoProvider).value ?? const [];
    LocationInfo? infoOf(ClassTime t) {
      final m = meetingFor(meetings, t);
      final i = m == null ? -1 : meetings.indexOf(m);
      return i >= 0 && infos.length == meetings.length ? infos[i] : null;
    }

    final walk = walkText(analysis, saved: data.fromSaved);
    final viewing = data.viewDay != null;
    final nextInfo = analysis.next == null ? null : infoOf(analysis.next!);
    final trip = !viewing && data.offCampus && data.arrivals.isNotEmpty;
    final showNextCard = trip || (walk != null && !viewing && analysis.next != null);
    final notes = [
      if (data.locationProblem != null) data.locationProblem!,
      if (data.reminderProblem != null) data.reminderProblem!,
      if (!viewing && data.offCampus && data.tripProblem != null) data.tripProblem!,
      if (!viewing && !trip) ...analysis.notes, // another day has no "next class" to walk to; a trip plan replaces the walk
    ];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.fromSaved) ...[_SavedBanner(data: data), const SizedBox(height: Space.sm)],
        _DayBar(viewDay: data.viewDay),
        Text(viewing ? dayViewSummary(analysis) : todaySummary(analysis), style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        if (analysis.banner != null && !trip) ...[_LeaveBanner(banner: analysis.banner!), const SizedBox(height: Space.sm)],
        if (showNextCard) _NextCard(data: data, building: nextInfo?.buildingName, walk: trip ? null : walk, unknownRoom: nextInfo?.isUnknown ?? false),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(note, style: theme.textTheme.bodyMedium),
          ),
        if (analysis.today.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text(viewing ? 'Classes on ${dayLabel(data.viewDay!)}' : "Today's classes", style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          for (final t in analysis.today.where((t) => !(showNextCard && analysis.next?.isToday == true && t.start == analysis.next!.start)))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _ClassTile(
                classTime: t,
                analysis: viewing ? null : analysis,
                arrival: viewing ? null : data.arrivals.where((a) => a.classTime.start == t.start).firstOrNull,
                unknownRoom: infoOf(t)?.isUnknown ?? false,
              ),
            ),
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
    final offline = data.offline;
    final lead = offline
        ? "Can't reach the server, so this is worked out on your phone."
        : 'Showing what is saved on this phone while the server answers.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusBanner(
          kind: offline ? BannerKind.offline : BannerKind.updating,
          title: offline ? 'Offline' : 'Updating…',
          body: '$lead ${data.savedNote ?? ''}'.trim(),
          actionLabel: offline ? 'Try again' : null,
          onAction: offline ? () => ref.read(todayProvider.notifier).refresh() : null,
        ),
        if (!offline) const WakingNote(),
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
    final today = DateTime.utc(nowPacific.year, nowPacific.month, nowPacific.day);
    final shown = viewDay ?? today;
    final (:first, :last) = scheduleSpan(meetings, today);
    final controller = ref.read(viewedDayProvider.notifier);
    DateTime step(int days) => DateTime.utc(shown.year, shown.month, shown.day + days);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            color: c.accentText,
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
            color: c.accentText,
            icon: const Icon(Icons.chevron_right),
            onPressed: shown.isBefore(last) ? () => controller.show(step(1)) : null,
          ),
          if (viewDay != null) TextButton(onPressed: controller.backToToday, child: const Text('Today')),
        ],
      ),
    );
  }
}

/// The next class as a card: when and where, how to get there, and the one button for it. Tapping the card
/// opens Going to class.
class _NextCard extends ConsumerWidget {
  const _NextCard({required this.data, this.building, this.walk, this.unknownRoom = false});

  final TodayData data;
  final String? building;

  /// The server could not place the room on the campus map.
  final bool unknownRoom;

  /// The walk from where the student is; null for a student off campus, who gets a trip instead.
  final ({String status, String text})? walk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final trip = walk == null ? data.arrivals.first : null;
    final next = trip?.classTime ?? data.analysis!.next!;
    final far = data.place == Whereabouts.far;
    final room = [next.location, if (building != null && building!.isNotEmpty) building!].join(' · ');
    return ClassCard(
      role: ClassRole.next,
      time: '${clockFromIso(next.start)}–${clockFromIso(next.end)}',
      title: next.label,
      room: room,
      header: _header(c, next, trip != null, far),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (next.location.isNotEmpty && !unknownRoom)
            IconButton(
              tooltip: 'Route to ${next.label}',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => openRoute(context, destination: RoomDestination(next.location)),
            ),
          if (DateTime.parse(next.end).isAfter(ref.read(clockProvider)()))
            PopupMenuButton<void>(
              tooltip: 'More for ${next.label}',
              itemBuilder: (_) => [PopupMenuItem<void>(onTap: () => skipClassDay(context, ref, next), child: const Text('Skip this day'))],
            ),
        ],
      ),
      arrival: unknownRoom ? null : trip?.headline,
      arrivalIcon: Icons.directions_bus_outlined,
      flag: unknownRoom ? "We can't find this room on the campus map." : null,
      extra: unknownRoom
          ? null
          : trip != null
          ? Text('${trip.walkMinutes} min on foot from there, plus ${trip.bufferMinutes} min to spare.', style: AppText.subhead.copyWith(color: c.labelPrimary))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(status: walk!.status),
                const SizedBox(width: Space.xs),
                Expanded(child: Text(walk!.text, style: AppText.subhead.copyWith(color: c.labelPrimary))),
              ],
            ),
      action: unknownRoom
          ? FilledButton.icon(
              onPressed: () => ref.read(selectedTabProvider.notifier).select(tabMap),
              icon: const Icon(Icons.search),
              label: const Text('Search the map'),
            )
          : trip != null
          ? TripActions(entry: trip.entry, options: trip.options, roomLabel: next.location, far: far)
          : (next.location.isEmpty
              ? null
              : FilledButton.icon(
                  onPressed: () => openRoute(context, destination: RoomDestination(next.location)),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Show route'),
                )),
      onTap: () => openGoingToClass(context),
    );
  }

  Widget? _header(AppColors c, ClassTime next, bool trip, bool far) {
    final transition = transitionText(next);
    if (!trip && transition == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trip) Text(far ? "You're far from campus" : "You're not on campus yet", style: AppText.subhead.copyWith(color: c.labelSecondary)),
        if (transition != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(status: transition.status),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(transition.text, style: AppText.footnote.copyWith(color: c.labelSecondary))),
            ],
          ),
      ],
    );
  }
}

class _LeaveBanner extends StatelessWidget {
  const _LeaveBanner({required this.banner});

  final LeaveBanner banner;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = banner.late ? c.statusLateFill : c.statusTightFill;
    final on = banner.late ? c.statusLateOn : c.statusTightOn;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(Radii.lg)),
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: Row(
            children: [
              Icon(Icons.directions_walk, color: on),
              const SizedBox(width: Space.sm),
              Expanded(child: Text(banner.text, style: AppText.headline.copyWith(color: on))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassTile extends ConsumerWidget {
  const _ClassTile({required this.classTime, required this.analysis, this.arrival, this.unknownRoom = false});

  final ClassTime classTime;

  /// The server could not place this class's room on the campus map.
  final bool unknownRoom;

  /// For a student off campus: when to be at an entry point for this class.
  final Arrival? arrival;

  /// Null when another day is shown, where nothing is "now" or "next".
  final Analysis? analysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final canSkip = DateTime.parse(classTime.end).isAfter(ref.read(clockProvider)());
    final isNow = analysis?.current?.start == classTime.start;
    final isNext = analysis?.next?.isToday == true && analysis?.next?.start == classTime.start;
    final transition = transitionText(classTime);
    return ClassCard(
      role: isNow ? ClassRole.now : (isNext ? ClassRole.next : ClassRole.later),
      time: '${clockFromIso(classTime.start)}–${clockFromIso(classTime.end)}',
      title: classTime.label,
      room: classTime.location,
      header: transition == null
          ? null
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(status: transition.status),
                const SizedBox(width: Space.xs),
                Expanded(child: Text(transition.text, style: AppText.footnote.copyWith(color: c.labelSecondary))),
              ],
            ),
      arrival: arrival?.headline,
      arrivalIcon: Icons.directions_bus_outlined,
      flag: unknownRoom ? "We can't find this room on the campus map." : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unknownRoom)
            TextButton(
              onPressed: () => ref.read(selectedTabProvider.notifier).select(tabMap),
              child: const Text('Search the map'),
            )
          else if (classTime.location.isNotEmpty)
            IconButton(
              tooltip: 'Route to ${classTime.label}',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => openRoute(context, destination: RoomDestination(classTime.location)),
            ),
          if (canSkip)
            PopupMenuButton<void>(
              tooltip: 'More for ${classTime.label}',
              itemBuilder: (_) => [
                PopupMenuItem<void>(onTap: () => skipClassDay(context, ref, classTime), child: const Text('Skip this day')),
              ],
            ),
        ],
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
            Text(body, style: theme.textTheme.bodyLarge?.copyWith(color: c.labelSecondary)),
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

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double width) => DecoratedBox(
          decoration: BoxDecoration(color: c.separator, borderRadius: BorderRadius.circular(6)),
          child: SizedBox(width: width, height: 12),
        );
    Widget placeholder(double width) => ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceContent,
              borderRadius: BorderRadius.circular(Radii.xl),
              border: Border.all(color: c.separator),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(120), const SizedBox(height: Space.sm), bar(width), const SizedBox(height: Space.sm), bar(100)],
              ),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(),
                SizedBox(height: Space.sm),
                Text('Working out your day…'),
                WakingNote(),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        placeholder(200),
        const SizedBox(height: Space.sm),
        placeholder(160),
      ],
    );
  }
}

/// Takes one class off one day, with an Undo.
Future<void> skipClassDay(BuildContext context, WidgetRef ref, ClassTime classTime) async {
  final meetings = ref.read(scheduleProvider).value ?? const [];
  final meeting = meetingFor(meetings, classTime);
  if (meeting == null) return;
  final messenger = ScaffoldMessenger.of(context); // the tile itself is gone once the class is skipped
  final day = classTime.start.substring(0, 10);
  final nowPacific = pacificTime(ref.read(clockProvider)());
  final schedule = ref.read(scheduleProvider.notifier);
  final skipped = await schedule.skipDay(meeting, day, today: isoDate(nowPacific));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(skipped
          ? 'Skipped ${classTime.label} on ${dayLabel(DateTime.parse(day))}.'
          : "Can't skip another day for ${classTime.label}: too many days are already skipped."),
      action: skipped ? SnackBarAction(label: 'Undo', onPressed: () => schedule.restoreDay(meeting, day)) : null,
    ));
}
