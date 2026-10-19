import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

var _ready = false;

/// UCSC's clock. Classes are on Pacific time wherever the phone happens to be set.
tz.Location get pacific {
  if (!_ready) {
    tz_data.initializeTimeZones();
    _ready = true;
  }
  return tz.getLocation('America/Los_Angeles');
}

tz.TZDateTime pacificTime(DateTime moment) => tz.TZDateTime.from(moment, pacific);

String _two(int n) => n.toString().padLeft(2, '0');

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// `2026-10-12T14:40:00-07:00`, the shape the server sends.
String isoWithOffset(tz.TZDateTime t) {
  final offset = t.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '-' : '+';
  return '${isoDate(t)}T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
}
