import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/tiles.dart';
import '../../design/controls.dart';
import '../../design/glass.dart';
import '../../design/surfaces.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../campus/campus_area.dart';
import '../handoff/trip_actions.dart';
import '../route/destination.dart';
import '../route/route_repository.dart';
import '../route/route_screen.dart';
import '../schedule/meeting.dart';
import '../schedule/schedule_controller.dart';
import '../today/today_controller.dart';
import '../today/today_models.dart';
import '../today/today_text.dart';

void openGoingToClass(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GoingToClassScreen()));
}

/// The next class, where it is, and the one thing to do about it: a glass card over the map with the time to
/// act on in large type.
class GoingToClassScreen extends ConsumerWidget {
  const GoingToClassScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(todayProvider).value;
    final next = data?.analysis?.next;
    final ready = data != null && next != null && next.isToday;
    final meetings = ref.watch(scheduleProvider).value ?? const <Meeting>[];
    final infos = ref.watch(locationInfoProvider).value ?? const <LocationInfo>[];
    final meeting = ready ? meetingFor(meetings, next) : null;
    final index = meeting == null ? -1 : meetings.indexOf(meeting);
    final info = index >= 0 && infos.length == meetings.length ? infos[index] : null;
    final unknown = info?.isUnknown ?? false;
    final hasRoom = ready && next.location.isNotEmpty && !unknown;
    final route = hasRoom ? ref.watch(routeProvider(RoomDestination(next.location))).value : null;
    final c = context.colors;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: route == null
                ? const _CampusMap()
                : RouteMap(plan: route.plan, entry: route.entry, fitPadding: const EdgeInsets.fromLTRB(48, 120, 48, 360)),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: ColoredBox(color: c.bgCanvas.withValues(alpha: 0.85)),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: GlassIconButton(
                  icon: Icons.arrow_back_ios_new,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
                  child: GlassSurface(
                    level: GlassLevel.strong,
                    strong: true,
                    padding: const EdgeInsets.all(Space.lg),
                    child: SingleChildScrollView(
                      child: ready
                          ? _Card(data: data, next: next, building: info?.buildingName, unknown: unknown)
                          : const _NothingNext(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampusMap extends StatelessWidget {
  const _CampusMap();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Campus map',
      child: FlutterMap(
        options: const MapOptions(initialCenter: LatLng(36.9951, -122.0585), initialZoom: 15),
        children: const [BaseMapLayer(), MapAttribution()],
      ),
    );
  }
}

class _NothingNext extends StatelessWidget {
  const _NothingNext();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Going to class', style: AppText.subhead.copyWith(color: c.labelSecondary))),
        const SizedBox(height: Space.xxs),
        Text('No class coming up today', style: AppText.title2.copyWith(color: c.labelPrimary)),
      ],
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.data, required this.next, required this.building, required this.unknown});

  final TodayData data;
  final ClassTime next;
  final String? building;
  final bool unknown;

  void _goTo(BuildContext context, WidgetRef ref, int tab) {
    ref.read(selectedTabProvider.notifier).select(tab);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final analysis = data.analysis!;
    final trip = data.offCampus ? data.arrivals.where((a) => a.classTime.start == next.start).firstOrNull : null;
    final walk = walkText(analysis, saved: data.fromSaved);
    final now = ref.watch(clockProvider)();

    String? heroLabel, heroTime, status, detail;
    if (trip != null) {
      final minutes = trip.arriveBy.difference(now).inMinutes;
      status = minutes < 0 ? 'late' : (minutes < 5 ? 'tight' : 'ok');
      heroLabel = 'Be at ${trip.entry.name} by';
      heroTime = trip.arriveByClock;
      detail = '${trip.walkMinutes} min on foot from there, plus ${trip.bufferMinutes} min to spare.';
    } else if (walk != null) {
      status = walk.status;
      detail = walk.text;
      if (analysis.leaveBy != null) {
        heroLabel = 'Leave by';
        heroTime = clockFromIso(analysis.leaveBy!);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, container: true, child: Text('Going to class', style: AppText.subhead.copyWith(color: c.labelSecondary))),
        const SizedBox(height: Space.xxs),
        Text(next.label, style: AppText.title1.copyWith(color: c.labelPrimary)),
        const SizedBox(height: Space.xxs),
        Text('${next.location} · starts ${clockFromIso(next.start)}', style: AppText.headline.copyWith(color: c.labelPrimary)),
        if (unknown || (building != null && building!.isNotEmpty))
          Text(unknown ? 'Building not recognized' : building!, style: AppText.subhead.copyWith(color: c.labelSecondary)),
        const SizedBox(height: Space.sm),
        if (unknown) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: c.statusTightFill),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("We can't find this room", style: AppText.title3.copyWith(color: c.labelPrimary)),
                    const SizedBox(height: Space.xxs),
                    Text(
                      "The campus map doesn't list ${next.location}. Search the map for the room, or check it on your schedule.",
                      style: AppText.subhead.copyWith(color: c.labelSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          FilledButton.icon(
            onPressed: () => _goTo(context, ref, tabMap),
            icon: const Icon(Icons.search),
            label: const Text('Search the map'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => _goTo(context, ref, tabSchedule), child: const Text('Edit class')),
          ),
        ] else ...[
          if (heroLabel != null && heroTime != null) ...[
            Text(heroLabel, style: AppText.subhead.copyWith(color: c.labelSecondary)),
            Text(heroTime, style: AppText.display.copyWith(color: c.labelPrimary)),
            const SizedBox(height: Space.xs),
          ],
          if (status != null && detail != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(status: status),
                const SizedBox(width: Space.xs),
                Expanded(child: Text(detail, style: AppText.subhead.copyWith(color: c.labelPrimary))),
              ],
            ),
          if (status == null && analysis.notes.isNotEmpty)
            for (final note in analysis.notes) Text(note, style: AppText.subhead.copyWith(color: c.labelSecondary)),
          const SizedBox(height: Space.sm),
          if (trip != null)
            TripActions(
              entry: trip.entry,
              options: trip.options,
              roomLabel: next.location,
              far: data.place == Whereabouts.far,
            )
          else if (next.location.isNotEmpty)
            FilledButton.icon(
              onPressed: () => openRoute(context, destination: RoomDestination(next.location)),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Show route'),
            ),
        ],
      ],
    );
  }
}
