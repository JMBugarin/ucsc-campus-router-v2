import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../location/location_service.dart';
import '../reminders/reminder_sync.dart';
import '../schedule/meeting.dart';
import '../schedule/schedule_controller.dart';
import '../settings/settings.dart';
import 'today_models.dart';
import 'today_repository.dart';

/// What the Today screen shows.
class TodayData {
  const TodayData({this.analysis, this.locationProblem, this.reminderProblem});

  /// Null when there are no classes yet.
  final Analysis? analysis;

  /// Why the phone's location could not be used (shown beside the result), if that happened.
  final String? locationProblem;

  /// Why reminders could not be set up on the phone, if that happened.
  final String? reminderProblem;

  bool get hasSchedule => analysis != null;
}

/// How often Today refreshes itself while it is open. Tests turn this off.
final todayRefreshIntervalProvider = Provider<Duration?>((ref) => const Duration(minutes: 1));

/// How long a GPS fix is reused instead of asking the phone again (saves battery).
const locationReuse = Duration(minutes: 2);

class TodayController extends AsyncNotifier<TodayData> {
  Timer? _timer;
  GeoPoint? _lastPoint;
  DateTime? _lastPointAt;
  final DateTime Function() _now = DateTime.now;

  @override
  Future<TodayData> build() async {
    final meetings = await ref.watch(scheduleProvider.future);
    final settings = ref.watch(settingsProvider);

    _timer?.cancel();
    final interval = ref.read(todayRefreshIntervalProvider);
    if (interval != null) _timer = Timer.periodic(interval, (_) => refresh(quiet: true));
    ref.onDispose(() => _timer?.cancel());

    return _compute(meetings, settings);
  }

  /// Recomputes now. A [quiet] refresh (the timer) keeps showing the last answer if it fails,
  /// rather than replacing a useful screen with an error; a manual refresh shows the error.
  Future<void> refresh({bool quiet = false}) async {
    final meetings = ref.read(scheduleProvider).value ?? const <Meeting>[];
    final settings = ref.read(settingsProvider);
    AsyncValue<TodayData> result;
    try {
      result = AsyncData(await _compute(meetings, settings));
    } catch (error, stackTrace) {
      result = AsyncError(error, stackTrace);
    }
    if (quiet && result.hasError && state.hasValue) return;
    state = result;
  }

  Future<TodayData> _compute(List<Meeting> meetings, Settings settings) async {
    final sync = ref.read(reminderSyncProvider);
    if (meetings.isEmpty) {
      await _cancelReminders(sync);
      return const TodayData();
    }

    GeoPoint? here;
    String? problem;
    if (settings.useLocation) {
      final lastAt = _lastPointAt;
      if (_lastPoint != null && lastAt != null && _now().difference(lastAt) < locationReuse) {
        here = _lastPoint;
      } else {
        final result = await ref.read(locationServiceProvider).current();
        here = result.point;
        problem = result.problem;
        if (here != null) {
          _lastPoint = here;
          _lastPointAt = _now();
        }
      }
    }

    final now = _now();
    final analysis = await ref.read(todayRepositoryProvider).today(
          meetings: meetings,
          here: here,
          remindLeadMinutes: settings.remindLeadMinutes,
          reminded: settings.remindersOn ? sync.firedKeys(now) : const [],
        );

    String? reminderProblem;
    try {
      if (settings.remindersOn) {
        await sync.apply(analysis.reminders, now);
      } else {
        await _cancelReminders(sync);
      }
    } on Object {
      // A notification problem must not hide the schedule.
      reminderProblem = "Couldn't set up leave-now reminders on this phone.";
    }
    return TodayData(analysis: analysis, locationProblem: problem, reminderProblem: reminderProblem);
  }

  Future<void> _cancelReminders(ReminderSync sync) async {
    if (!sync.hasAny) return;
    try {
      await sync.clear(_now());
    } on Object {
      // nothing useful to do; the reminders would just not be cancelled
    }
  }
}

final todayProvider = AsyncNotifierProvider<TodayController, TodayData>(TodayController.new);
