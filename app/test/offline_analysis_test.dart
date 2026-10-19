import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/today/offline_analysis.dart';
import 'package:ucsc_router/features/today/today_models.dart';
import 'package:ucsc_router/features/today/walk_cache.dart';

import 'helpers.dart';

void main() {
  final data = jsonDecode(File('../server/testdata/schedule_cases.json').readAsStringSync()) as Map<String, dynamic>;

  Future<WalkCache> cacheWith(Map<String, dynamic> walks) async {
    SharedPreferences.setMockInitialValues({
      'walk_cache_v1': jsonEncode({'walks': walks}),
    });
    return WalkCache(await SharedPreferences.getInstance());
  }

  group('the same cases as the server', () {
    final holidays = {for (final h in data['holidays'] as List) h as String};
    for (final raw in data['cases'] as List) {
      final c = raw as Map<String, dynamic>;
      test(c['name'] as String, () async {
        final meetings = [
          for (final n in c['meetings'] as List) Meeting.fromJson((data['meetings'] as Map)[n] as Map<String, dynamic>),
        ];
        final a = analyzeOffline(
          meetings: meetings,
          now: DateTime.parse(c['now'] as String),
          holidays: holidays,
          walks: await cacheWith(data['walks'] as Map<String, dynamic>),
          hasLocation: c['here'] as bool,
        );
        final want = c['expect'] as Map<String, dynamic>;
        expect(a.state, want['state']);
        expect(a.reason, want['reason']);
        expect(a.current?.start, want['current_start']);
        expect(a.next?.start, want['next_start']);
        expect(a.next?.isToday, want['next_is_today']);
        expect(a.next?.startsInMin, (want['starts_in_min'] as num?)?.toDouble());
        expect([for (final t in a.today) t.start], want['today_starts']);
        expect(a.walk?.minutes, want['walk_minutes']);
        expect(a.walk?.from, want['walk_from']);
        expect(a.freeMin, (want['free_min'] as num?)?.toDouble());
        expect(a.status, want['status']);
        expect(a.leaveBy, want['leave_by']);
        final transitions = [
          for (final t in a.today.skip(1)) {'walk_min': t.walkMin, 'free_min': t.freeMin, 'status': t.status},
        ];
        expect(jsonEncode(transitions), jsonEncode(want['transitions']));
      });
    }
  });

  group('WalkCache', () {
    late WalkCache cache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cache = WalkCache(await SharedPreferences.getInstance());
    });

    test('learns the walk to the next class and between classes from a server answer', () async {
      final analysis = Analysis.fromJson(fixture('today_reminders_all_day'));
      await cache.remember(analysis);
      expect(cache.hasAny, isTrue);
      expect(cache.minutes(null, 'Kresge Acad 3201'), 12);
      expect(cache.minutes('Kresge Acad 3201', 'Soc Sci 2 075'), 12);
      expect(cache.minutes('Soc Sci 2 075', 'Kresge Acad 3201'), 12);
      expect(cache.minutes('Nowhere 1', 'Kresge Acad 3201'), isNull);
    });

    test('an unknown destination has no walk, and a position-only query falls back to any known walk', () async {
      await cache.remember(Analysis.fromJson(fixture('today_before_class')));
      expect(cache.minutes(null, 'Somewhere Else 9'), isNull);
      expect(cache.minutes(null, 'Kresge Acad 3201'), isNotNull);
    });

    test('keeps the holidays the server sent', () async {
      final json = fixture('today_before_class')..['holidays'] = ['2026-11-11'];
      await cache.remember(Analysis.fromJson(json));
      expect(cache.holidays, {'2026-11-11'});
      await cache.remember(Analysis.fromJson(fixture('today_before_class')));
      expect(cache.holidays, {'2026-11-11'}, reason: 'an answer without holidays does not erase them');
    });

    test('a broken store is treated as empty', () async {
      SharedPreferences.setMockInitialValues({'walk_cache_v1': 'not json'});
      final broken = WalkCache(await SharedPreferences.getInstance());
      expect(broken.minutes(null, 'x'), isNull);
      expect(broken.holidays, isEmpty);
    });
  });
}
