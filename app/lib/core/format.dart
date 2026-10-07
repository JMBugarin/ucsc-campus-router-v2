/// Shows an ISO time such as `2026-10-12T14:40:00-07:00` as `2:40 PM`.
///
/// The server sends Pacific times with their offset. They are read straight out of the
/// text instead of being converted, so the clock on the screen is the campus clock even if
/// the phone is set to another time zone.
String clockFromIso(String iso) {
  final match = RegExp(r'T(\d{2}):(\d{2})').firstMatch(iso);
  if (match == null) return iso;
  return clock12(int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// `14:40` as `2:40 PM`.
String clockFromHhmm(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  return clock12(int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
}

String clock12(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  final period = hour < 12 ? 'AM' : 'PM';
  return '$h:${minute.toString().padLeft(2, '0')} $period';
}

/// `95` as `1 h 35 min`; under a minute as `less than a minute`.
String durationText(num minutes) {
  final total = minutes.round();
  if (total < 1) return 'less than a minute';
  if (total < 60) return '$total min';
  final h = total ~/ 60;
  final m = total % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The weekday of an ISO date or time (`2026-10-12...`), as `Mon`.
String weekdayFromIso(String iso) {
  final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  if (match == null) return '';
  final date = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[date.weekday - 1];
}

const dayCodes = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
