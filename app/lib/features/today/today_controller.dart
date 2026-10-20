import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/pacific.dart';
import 'package:timezone/timezone.dart' as tz;
import '../location/location_service.dart';
import '../reminders/reminder_sync.dart';
import '../schedule/meeting.dart';
import '../schedule/schedule_controller.dart';
import '../settings/settings.dart';
import 'offline_analysis.dart';
import 'today_models.dart';
import 'walk_cache.dart';
import 'today_repository.dart';

/// What the Today screen shows.
class TodayData {
  const TodayData({this.analysis, this.locationProblem, this.reminderProblem, this.offline = false, this.viewDay});

  /// Set when the day picker is showing a day other than today.
  final DateTime? viewDay;

  /// Null when there are no classes yet.
  final Analysis? analysis;

  /// Why the phone's location could not be used (shown beside the result), if that happened.
  final String? locationProblem;

  /// Why reminders could not be set up on the phone, if that happened.
  final String? reminderProblem;

  /// True when the server could not be reached and this was worked out on the phone from the saved
  /// schedule and the walk times saved from the last time it was reachable.
  final bool offline;

  bool get hasSchedule => analysis != null;
}

/// The day the day picker is showing; null means today (whatever today is when you look).
class ViewedDay extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void show(DateTime day) {
    final picked = DateTime.utc(day.year, day.month, day.day);
    final now = pacificTime(DateTime.now());
    state = isoDate(picked) == isoDate(now) ? null : picked;
  }

  void backToToday() => state = null;
}

final viewedDayProvider = NotifierProvider<ViewedDay, DateTime?>(ViewedDay.new);

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
    final viewDay = ref.watch(viewedDayProvider);

    _timer?.cancel();
    final interval = ref.read(todayRefreshIntervalProvider);
    if (interval != null) _timer = Timer.periodic(interval, (_) => refresh(quiet: true));
    ref.onDispose(() => _timer?.cancel());

    return _guarded(() => _compute(meetings, settings, viewDay));
  }

  /// Recomputes now. A [quiet] refresh (the timer) keeps showing the last answer if it fails,
  /// rather than replacing a useful screen with an error; a manual refresh shows the error.
  /// A quiet refresh is skipped while another is still waiting, so a server that is slow to wake
  /// does not collect a pile of identical requests.
  Future<void> refresh({bool quiet = false}) async {
    if (quiet && _inFlight > 0) return;
    final meetings = ref.read(scheduleProvider).value ?? const <Meeting>[];
    final settings = ref.read(settingsProvider);
    AsyncValue<TodayData> result;
    try {
      result = AsyncData(await _guarded(() => _compute(meetings, settings, ref.read(viewedDayProvider))));
    } catch (error, stackTrace) {
      result = AsyncError(error, stackTrace);
    }
    if (quiet && result.hasError && state.hasValue) return;
    state = result;
  }

  var _inFlight = 0;

  Future<TodayData> _guarded(Future<TodayData> Function() job) async {
    _inFlight++;
    try {
      return await job();
    } finally {
      _inFlight--;
    }
  }

  Future<TodayData> _compute(List<Meeting> meetings, Settings settings, DateTime? viewDay) async {
    final sync = ref.read(reminderSyncProvider);
    if (viewDay != null) return _computeDay(meetings, viewDay);
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
    final Analysis analysis;
    try {
      analysis = await ref.read(todayRepositoryProvider).today(
            meetings: meetings,
            here: here,
            remindLeadMinutes: settings.remindLeadMinutes,
            reminded: settings.remindersOn ? sync.firedKeys(now) : const [],
          );
    } on ApiException catch (error) {
      final unreachable = error.kind == ApiErrorKind.offline ||
          error.kind == ApiErrorKind.timeout ||
          error.kind == ApiErrorKind.server;
      if (!unreachable) rethrow;
      final walks = ref.read(walkCacheProvider);
      // Reminders already on the phone stay as they were; nothing new can be planned without the server.
      return TodayData(
        analysis: analyzeOffline(
          meetings: meetings,
          now: now,
          holidays: walks.holidays,
          walks: walks,
          hasLocation: here != null,
        ),
        locationProblem: problem,
        offline: true,
      );
    }
    unawaited(ref.read(walkCacheProvider).remember(analysis));

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

  /// Another day's classes. It never touches the phone's location or reminders, which are about now.
  Future<TodayData> _computeDay(List<Meeting> meetings, DateTime day) async {
    if (meetings.isEmpty) return TodayData(viewDay: day);
    final at = tz.TZDateTime(pacific, day.year, day.month, day.day, 0, 1);
    Analysis analysis;
    var offline = false;
    try {
      analysis = await ref.read(todayRepositoryProvider).today(meetings: meetings, at: at);
    } on ApiException catch (error) {
      final unreachable = error.kind == ApiErrorKind.offline ||
          error.kind == ApiErrorKind.timeout ||
          error.kind == ApiErrorKind.server;
      if (!unreachable) rethrow;
      final walks = ref.read(walkCacheProvider);
      analysis = analyzeOffline(meetings: meetings, now: at, holidays: walks.holidays, walks: walks, hasLocation: false);
      offline = true;
    }
    return TodayData(analysis: analysis, offline: offline, viewDay: day);
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
