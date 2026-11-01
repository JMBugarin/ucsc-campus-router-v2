import 'package:classmap/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('time and duration text', () {
    test('clocks are read from the ISO text, not converted', () {
      expect(clockFromIso('2026-10-12T14:40:00-07:00'), '2:40 PM');
      expect(clockFromIso('2026-10-12T00:05:00-07:00'), '12:05 AM');
      expect(clockFromIso('2026-10-12T12:00:00-07:00'), '12:00 PM');
      expect(clockFromIso('2026-12-01T09:05:00-08:00'), '9:05 AM');
      expect(clockFromIso('not a time'), 'not a time');
      expect(clockFromHhmm('08:00'), '8:00 AM');
      expect(clockFromHhmm('16:00'), '4:00 PM');
    });

    test('durations', () {
      expect(durationText(0.2), 'less than a minute');
      expect(durationText(5), '5 min');
      expect(durationText(59.6), '1 h');
      expect(durationText(60), '1 h');
      expect(durationText(95), '1 h 35 min');
    });

    test('weekday of an ISO time', () {
      expect(weekdayFromIso('2026-10-12T14:40:00-07:00'), 'Mon');
      expect(weekdayFromIso('2026-10-14T08:00:00-07:00'), 'Wed');
      expect(weekdayFromIso('nonsense'), '');
    });
  });
}
