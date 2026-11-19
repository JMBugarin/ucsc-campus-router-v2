import 'package:classmap/features/search/search_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('housing', () {
    String? first(String q) => testHousing.search(q).firstOrNull?.$1.name;

    test('is found by the names students use', () {
      expect(first('c9 apt 2'), 'College Nine Apartment Building 2');
      expect(
        first('college 9 apartment building 2'),
        'College Nine Apartment Building 2',
      );
      expect(first('galileo'), 'Crown College Galileo House');
      expect(first('casa primera'), 'Stevenson College House 1');
      expect(first('merrill dubois'), 'Merrill College House D');
      expect(first('village b1'), 'Village Housing B1');
      expect(
        first('rcc a building'),
        'Rachel Carson College Dorm A-L-Building',
      );
      expect(testHousing.search('zzzz'), isEmpty);
    });

    test('mixes with buildings and rooms without pushing them down', () async {
      final repo = LocalSearchRepository(
        () async => testCampus,
        () async => testHousing,
      );
      final apt = await repo.search('c9 apt 2');
      expect(apt.first.label, 'College Nine Apartment Building 2');
      expect(apt.first.isHousing, isTrue);
      expect(apt.first.subtitle, 'Housing · College Nine');
      expect(
        (await repo.search('BE 152')).first.label,
        'Jack Baskin Engineering 152',
      );
      expect((await repo.search('crown')).first.isHousing, isFalse);
      expect(
        (await repo.search('crown galileo')).first.label,
        'Crown College Galileo House',
      );
    });

    test('every building has a point on campus and a unique id', () {
      final ids = {for (final h in testHousing.all) h.id};
      expect(ids.length, testHousing.all.length);
      expect(testHousing.all.length, greaterThan(150));
      for (final h in testHousing.all) {
        expect(h.point.lat, inInclusiveRange(36.97, 37.01), reason: h.name);
        expect(
          h.point.lon,
          inInclusiveRange(-122.075, -122.04),
          reason: h.name,
        );
      }
      expect(
        testHousing.byId('crown-college-galileo-house')?.short,
        'Galileo House',
      );
      expect(testHousing.byId(null), isNull);
    });
  });
}
