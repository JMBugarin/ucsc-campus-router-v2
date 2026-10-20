import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/features/arrive/arrival.dart';
import 'package:ucsc_router/features/arrive/entry_walks.dart';
import 'package:ucsc_router/features/campus/campus_area.dart';
import 'package:ucsc_router/features/location/location_service.dart';
import 'package:ucsc_router/features/today/today_controller.dart';
import 'package:ucsc_router/features/today/today_models.dart';

import 'controllers_test.dart' show mondayNoon;
import 'helpers.dart';

const campus = GeoPoint(36.9998, -122.0628);
const downtown = GeoPoint(36.9741, -122.0308);
const westside = GeoPoint(36.9526, -122.0650);
const capitola = GeoPoint(36.9752, -121.9533);
const scottsValley = GeoPoint(37.0510, -122.0147);
const sanFrancisco = GeoPoint(37.7749, -122.4194);

final walks = EntryWalks.fromJson(fixture('entry_walks'));
const lecture = 'Kresge Acad 3201';

ClassTime classAt(String start, {String location = lecture}) => ClassTime(
      course: 'XYZ 10',
      component: 'Lecture',
      location: location,
      start: start,
      end: '2026-10-12T15:45:00-07:00',
    );

void main() {
  group('where a phone is', () {
    test('the campus area is the area the server routes in', () {
      final meta = jsonDecode(File('../graph/ucsc/meta.json').readAsStringSync()) as Map<String, dynamic>;
      expect(meta['bbox_west_south_east_north'], [campusWest, campusSouth, campusEast, campusNorth]);
    });

    final cases = [
      ('on campus', campus, Whereabouts.onCampus),
      ('just outside the graph, inside the margin', GeoPoint(36.9855, -122.058), Whereabouts.onCampus),
      ('downtown Santa Cruz', downtown, Whereabouts.offCampus),
      ('Westside', westside, Whereabouts.offCampus),
      ('Capitola', capitola, Whereabouts.offCampus),
      ('Scotts Valley', scottsValley, Whereabouts.offCampus),
      ('San Francisco', sanFrancisco, Whereabouts.far),
    ];
    for (final (name, point, expected) in cases) {
      test(name, () => expect(whereIs(point), expected));
    }

    test('distances are in kilometres', () {
      expect(distanceKm(downtown, campusCenter), closeTo(3.3, 0.3));
      expect(distanceKm(campus, campus), 0);
    });
  });

  group('entry point walks', () {
    test('read what the server sends', () {
      expect(walks.buildingName, 'Kresge College Academic Building');
      expect(walks.walks.first.entry.id, 'kerr-hall-bus-stop');
      expect(walks.walks.first.minutes, 10);
      expect(walks.walks.first.entry.isBusStop, isTrue);
      expect(walks.walks.any((w) => !w.entry.isBusStop), isTrue);
      expect(EntryWalks.fromJson(walks.toJson()).walks.map((w) => w.minutes), walks.walks.map((w) => w.minutes));
    });

    test('the nearest entry point to the student comes first, and without a location the shortest walk does', () {
      final nearKresge = orderEntries(walks.walks, const GeoPoint(36.9992, -122.0645));
      expect(nearKresge.first.entry.id, 'kresge-college-bus-stop');
      final byWalk = orderEntries(walks.walks, null);
      expect(byWalk.map((w) => w.minutes), [...byWalk.map((w) => w.minutes)]..sort());
    });

    test('an entry point next door with a long walk to class is offered after the better ones', () {
      final far = walks.walks.where((w) => w.minutes > walks.walks.first.minutes + reasonableExtraWalkMinutes).toList();
      expect(far, isNotEmpty, reason: 'the fixture has a stop with a much longer walk');
      final atFar = far.first.entry.point;
      final ordered = orderEntries(walks.walks, atFar);
      expect(ordered.first.entry.id, isNot(far.first.entry.id));
      expect(ordered.last.minutes, greaterThan(walks.walks.first.minutes + reasonableExtraWalkMinutes));
    });

    test('a remembered choice is used while it is still on offer', () {
      final ordered = orderEntries(walks.walks, downtown);
      expect(chooseEntry(ordered, ordered.last.entry.id).entry.id, ordered.last.entry.id);
      expect(chooseEntry(ordered, 'gone').entry.id, ordered.first.entry.id);
      expect(chooseEntry(ordered, null).entry.id, ordered.first.entry.id);
    });
  });

  group('arriving by', () {
    test('class start minus the campus walk and the off-campus buffer', () {
      final arrival = planArrival(
        classTime: classAt('2026-10-12T14:40:00-07:00'),
        walks: walks,
        chosenId: 'kerr-hall-bus-stop',
      );
      expect(arrival.walkMinutes, 10);
      expect(arrival.bufferMinutes, offCampusBufferMinutes);
      expect(arrival.arriveByClock, '2:20 PM');
      expect(arrival.headline, 'Be at Kerr Hall bus stop by 2:20 PM');
    });

    test('another entry point changes the time', () {
      final arrival = planArrival(classTime: classAt('2026-10-12T14:40:00-07:00'), walks: walks, chosenId: 'kerr-hall-bus-stop');
      final other = walks.walks.firstWhere((w) => w.minutes > 10);
      final moved = withEntry(arrival, other);
      expect(moved.entry.id, other.entry.id);
      expect(moved.arriveBy, arrival.arriveBy.subtract(Duration(minutes: other.minutes - 10)));
    });

    test('the time is the campus clock whatever the phone is set to', () {
      final arrival = planArrival(classTime: classAt('2026-10-12T08:00:00-07:00'), walks: walks, chosenId: 'kerr-hall-bus-stop');
      expect(arrival.arriveByClock, '7:40 AM');
    });

    test('reminders come before the time to be there, and are keyed like the server keys them', () {
      final arrival = planArrival(classTime: classAt('2026-10-12T14:40:00-07:00'), walks: walks, chosenId: 'kerr-hall-bus-stop');
      final plan = arrivalReminders([arrival], mondayNoon);
      expect(plan.map((r) => r.stage), ['heads-up', 'leave']);
      expect(plan.map((r) => r.key), ['2026-10-12T14:40:00-07:00|heads-up', '2026-10-12T14:40:00-07:00|leave']);
      expect(plan[0].inSeconds, 110 * 60, reason: '13:50, half an hour before 2:20 PM');
      expect(plan[1].inSeconds, 130 * 60, reason: '14:10, ten minutes before 2:20 PM');
      expect(plan[0].title, contains('Be at Kerr Hall bus stop by 2:20 PM'));
      expect(plan[1].title, 'Be at Kerr Hall bus stop by 2:20 PM');
    });

    test('a reminder already shown, or already past, is not planned, and 0 turns the early one off', () {
      final arrival = planArrival(classTime: classAt('2026-10-12T14:40:00-07:00'), walks: walks, chosenId: 'kerr-hall-bus-stop');
      final sent = {'2026-10-12T14:40:00-07:00|heads-up'};
      expect(arrivalReminders([arrival], mondayNoon, sent: sent).map((r) => r.stage), ['leave']);
      expect(arrivalReminders([arrival], mondayNoon, leadMinutes: 0).map((r) => r.stage), ['leave']);
      final late = DateTime.utc(2026, 10, 12, 21, 30);
      expect(arrivalReminders([arrival], late), isEmpty);
    });
  });

  group('the walk times are kept for a bad connection', () {
    Future<(EntryWalksService, FakeEntryWalksRepository)> service({DateTime Function()? clock}) async {
      SharedPreferences.setMockInitialValues({});
      final repo = FakeEntryWalksRepository();
      return (EntryWalksService(repo, EntryWalksCache(await SharedPreferences.getInstance()), clock: clock), repo);
    }

    test('an offline server falls back to the last answer for that room', () async {
      final (s, repo) = await service();
      await s.forRoom(lecture);
      repo.answer = const ApiException('offline', kind: ApiErrorKind.offline);
      final fresh = EntryWalksService(repo, EntryWalksCache(await SharedPreferences.getInstance()));
      expect((await fresh.forRoom(lecture)).walks.length, walks.walks.length);
      await expectLater(fresh.forRoom('Other Hall 1'), throwsA(isA<ApiException>()));
    });

    test('a server that does not know the path is unavailable, not a crash', () async {
      final api = ApiClient(baseUrl: 'https://x.example', client: _status(404, '{"error": "unknown endpoint"}'));
      await expectLater(ApiEntryWalksRepository(api).to(lecture), throwsA(isA<EntryWalksUnavailable>()));
      final empty = ApiClient(baseUrl: 'https://x.example', client: _status(200, '{"room": {}, "entry_points": []}'));
      await expectLater(ApiEntryWalksRepository(empty).to(lecture), throwsA(isA<EntryWalksUnavailable>()));
    });

    test('the request carries the room and nothing else', () async {
      late Uri seen;
      final api = ApiClient(
        baseUrl: 'https://x.example',
        client: _recording((u) => seen = u, jsonEncode(fixture('entry_walks'))),
      );
      await ApiEntryWalksRepository(api).to(lecture);
      expect(seen.path, '/api/entry_walks');
      expect(seen.queryParameters, {'room': lecture});
    });

    test('a room asked about a moment ago is not asked about again', () async {
      var now = DateTime.utc(2026, 10, 12, 19);
      final (s, repo) = await service(clock: () => now);
      await s.forRoom(lecture);
      await s.forRoom(lecture);
      expect(repo.requests, [lecture]);
      now = now.add(EntryWalksService.recentFor + const Duration(minutes: 1));
      await s.forRoom(lecture);
      expect(repo.requests, [lecture, lecture]);
    });
  });

  group('today for a student off campus', () {
    Future<(TestRig, TodayData)> run({
      GeoPoint at = downtown,
      bool remindersOn = false,
      Map<String, Object> prefs = const {},
      void Function(TestRig rig)? setUp,
    }) async {
      final rig = TestRig(
        stored: [meeting(), meeting(course: 'ABC 20', start: '16:00', end: '17:05', location: 'Thim Lecture 003')],
        now: mondayNoon,
        remindersOn: remindersOn,
        prefs: prefs,
      );
      rig.location.result = LocationResult.found(at);
      setUp?.call(rig);
      final container = await rig.container();
      addTearDown(container.dispose);
      return (rig, await container.read(todayProvider.future));
    }

    test('the server never receives where the student is, only room names', () async {
      final (rig, data) = await run();
      expect(rig.today.requests.single.here, isNull);
      expect(rig.entryWalks.requests.toSet(), {lecture, 'Thim Lecture 003'});
      expect(data.offCampus, isTrue);
      expect(data.place, Whereabouts.offCampus);
    });

    test('each class still to come gets a time to be at an entry point', () async {
      final (_, data) = await run();
      expect(data.arrivals.map((a) => a.classTime.location), [lecture, 'Thim Lecture 003']);
      for (final a in data.arrivals) {
        expect(a.options.length, walks.walks.length);
        expect(a.bufferMinutes, offCampusBufferMinutes);
      }
    });

    test('the remembered entry point is the one planned for', () async {
      final (_, data) = await run(prefs: {'entry_point_choice': 'core-west-parking'});
      expect(data.arrivals.first.entry.id, 'core-west-parking');
    });

    test('a faraway phone is told so but still gets the times', () async {
      final (rig, data) = await run(at: sanFrancisco);
      expect(data.place, Whereabouts.far);
      expect(rig.today.requests.single.here, isNull);
      expect(data.arrivals, isNotEmpty);
    });

    test('on campus nothing changes: the location is sent and no entry point is asked about', () async {
      final (rig, data) = await run(at: campus);
      expect(rig.today.requests.single.here, campus);
      expect(rig.entryWalks.requests, isEmpty);
      expect(data.offCampus, isFalse);
      expect(data.arrivals, isEmpty);
      expect(data.tripProblem, isNull);
    });

    test('an older server leaves the plain Today and says why', () async {
      final (_, data) = await run(setUp: (rig) => rig.entryWalks.answer = const EntryWalksUnavailable());
      expect(data.analysis, isNotNull);
      expect(data.arrivals, isEmpty);
      expect(data.tripProblem, const EntryWalksUnavailable().message);
    });

    test('a room with nowhere to walk to is skipped without an error', () async {
      final (_, data) = await run(
        setUp: (rig) => rig.entryWalks.byRoom['Thim Lecture 003'] =
            const ApiException('that class is online, so there is nowhere to walk', kind: ApiErrorKind.rejected),
      );
      expect(data.arrivals.map((a) => a.classTime.location), [lecture]);
      expect(data.tripProblem, isNull);
    });

    test('with no connection the times saved for those rooms are used', () async {
      final saved = jsonEncode({for (final room in [lecture, 'Thim Lecture 003']) room: walks.toJson()});
      final (rig, data) = await run(
        prefs: {'entry_walks_v1': saved},
        setUp: (rig) {
          rig.entryWalks.answer = const ApiException('offline', kind: ApiErrorKind.offline);
          rig.today.answer = const ApiException('offline', kind: ApiErrorKind.offline);
        },
      );
      expect(data.offline, isTrue);
      expect(data.arrivals, hasLength(2));
      expect(rig.entryWalks.requests, isNotEmpty);
    });

    test('reminders use the time to be at the entry point', () async {
      final (rig, _) = await run(remindersOn: true, prefs: {'entry_point_choice': 'kerr-hall-bus-stop'});
      final leave = rig.scheduler.scheduled['2026-10-12T14:40:00-07:00|leave'];
      final early = rig.scheduler.scheduled['2026-10-12T14:40:00-07:00|heads-up'];
      expect(leave, DateTime.utc(2026, 10, 12, 21, 10));
      expect(early, DateTime.utc(2026, 10, 12, 20, 50));
    });

    test('on campus reminders are the server\'s, as before', () async {
      final (rig, _) = await run(at: campus, remindersOn: true);
      expect(rig.scheduler.scheduled.keys.every((k) => !k.contains('Be at')), isTrue);
      expect(rig.entryWalks.requests, isEmpty);
    });
  });
}

MockClient _status(int code, String body) => MockClient((_) async => http.Response(body, code));

MockClient _recording(void Function(Uri) onUri, String body) => MockClient((request) async {
      onUri(request.url);
      return http.Response(body, 200);
    });
