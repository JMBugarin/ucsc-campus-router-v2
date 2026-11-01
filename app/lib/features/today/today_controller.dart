import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../campus/campus_data.dart';
import '../../campus/terms.dart';
import '../../core/clock.dart';
import '../../core/pacific.dart';
import '../schedule/schedule_controller.dart';
import 'day_plan.dart';

/// The day the day picker is showing; null means today (whatever today is when you look).
class ViewedDay extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void show(DateTime day) {
    final picked = DateTime.utc(day.year, day.month, day.day);
    final now = pacificTime(ref.read(clockProvider)());
    state = isoDate(picked) == isoDate(now) ? null : picked;
  }

  void backToToday() => state = null;
}

final viewedDayProvider = NotifierProvider<ViewedDay, DateTime?>(ViewedDay.new);

/// How often the clock on Today ticks. Tests turn this off.
final todayRefreshIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(minutes: 1),
);

/// The current time, refreshed every minute so "in 40 min" stays right.
class MinuteClock extends Notifier<DateTime> {
  @override
  DateTime build() {
    final interval = ref.watch(todayRefreshIntervalProvider);
    if (interval != null) {
      final timer = Timer.periodic(
        interval,
        (_) => state = ref.read(clockProvider)(),
      );
      ref.onDispose(timer.cancel);
    }
    return ref.read(clockProvider)();
  }

  void refresh() => state = ref.read(clockProvider)();
}

final nowProvider = NotifierProvider<MinuteClock, DateTime>(MinuteClock.new);

/// What Today shows: worked out on the phone from the saved schedule and the clock.
final dayPlanProvider = Provider<AsyncValue<DayPlan>>((ref) {
  final meetings = ref.watch(scheduleProvider);
  final terms = ref.watch(termsProvider);
  final viewDay = ref.watch(viewedDayProvider);
  final now = ref.watch(nowProvider);
  if (meetings.hasError) {
    return AsyncError(
      meetings.error!,
      meetings.stackTrace ?? StackTrace.current,
    );
  }
  if (!meetings.hasValue || !terms.hasValue) return const AsyncLoading();
  return AsyncData(
    planDay(
      meetings: meetings.requireValue,
      now: now,
      holidays: holidaysOf(terms.requireValue),
      viewDay: viewDay,
    ),
  );
});
