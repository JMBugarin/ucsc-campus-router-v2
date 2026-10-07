import '../../core/format.dart';

/// One weekly class meeting (or a one-off event), in the same shape the server uses.
///
/// `days` are weekday numbers with 0 = Monday. A meeting with no days is a one-off event on
/// [startDate]. Times are 24-hour `HH:MM`, dates are `YYYY-MM-DD`, all Pacific time.
class Meeting {
  const Meeting({
    required this.course,
    this.title = '',
    this.section = '',
    this.component = '',
    this.classNbr = '',
    required this.days,
    required this.start,
    required this.end,
    this.location = '',
    required this.startDate,
    required this.endDate,
    this.skipDates = const [],
  });

  final String course;
  final String title;
  final String section;
  final String component;
  final String classNbr;
  final List<int> days;
  final String start;
  final String end;
  final String location;
  final String startDate;
  final String endDate;
  final List<String> skipDates;

  factory Meeting.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] as String?) ?? '';
    return Meeting(
      course: text('course'),
      title: text('title'),
      section: text('section'),
      component: text('component'),
      classNbr: text('class_nbr'),
      days: [for (final d in (json['days'] as List? ?? const [])) (d as num).toInt()],
      start: text('start'),
      end: text('end'),
      location: text('location'),
      startDate: text('start_date'),
      endDate: text('end_date'),
      skipDates: [for (final d in (json['skip_dates'] as List? ?? const [])) d as String],
    );
  }

  Map<String, dynamic> toJson() => {
        'course': course,
        'title': title,
        'section': section,
        'component': component,
        'class_nbr': classNbr,
        'days': days,
        'start': start,
        'end': end,
        'location': location,
        'start_date': startDate,
        'end_date': endDate,
        if (skipDates.isNotEmpty) 'skip_dates': skipDates,
      };

  /// `XYZ 10 Lecture`.
  String get label => [course, component].where((s) => s.isNotEmpty).join(' ');

  /// `MoWeFr`, or the date for a one-off event.
  String get whenLabel => days.isEmpty ? startDate : days.map((d) => dayCodes[d]).join();

  /// `2:40 PM–3:45 PM`.
  String get timeLabel => '${clockFromHhmm(start)}–${clockFromHhmm(end)}';

  /// True if [other] is the same class (so importing the same schedule twice adds nothing).
  bool sameClassAs(Meeting other) =>
      course == other.course &&
      component == other.component &&
      section == other.section &&
      _sameDays(other) &&
      start == other.start &&
      end == other.end &&
      location == other.location &&
      startDate == other.startDate;

  bool _sameDays(Meeting other) =>
      days.length == other.days.length && [for (var i = 0; i < days.length; i++) days[i] == other.days[i]].every((b) => b);
}

/// What the server made of a meeting's location text.
class LocationInfo {
  const LocationInfo({required this.kind, this.buildingName, this.roomKnown});

  /// `building`, `online`, `tba` or `unknown`.
  final String kind;
  final String? buildingName;
  final bool? roomKnown;

  factory LocationInfo.fromJson(Map<String, dynamic> json) => LocationInfo(
        kind: (json['kind'] as String?) ?? 'unknown',
        buildingName: json['building_name'] as String?,
        roomKnown: json['room_known'] as bool?,
      );

  bool get isUnknown => kind == 'unknown';
}

/// The result of reading a schedule from text or a calendar file.
class ImportResult {
  const ImportResult({required this.meetings, required this.notes, required this.locations});

  final List<Meeting> meetings;
  final List<String> notes;
  final List<LocationInfo> locations;

  factory ImportResult.fromJson(Map<String, dynamic> json) => ImportResult(
        meetings: [for (final m in (json['meetings'] as List? ?? const [])) Meeting.fromJson(m as Map<String, dynamic>)],
        notes: [for (final n in (json['notes'] as List? ?? const [])) n as String],
        locations: [for (final l in (json['locations'] as List? ?? const [])) LocationInfo.fromJson(l as Map<String, dynamic>)],
      );
}
