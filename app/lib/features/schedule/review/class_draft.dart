import '../../../core/format.dart';
import '../meeting.dart';
import '../ocr/parsed_row.dart';

String _tidy(String text) => text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

/// A class read from a picture, while the student checks it. Nothing here is saved until they say so.
class ClassDraft {
  const ClassDraft({
    required this.id,
    this.course = '',
    this.title = '',
    this.section = '',
    this.component = '',
    this.days = const [],
    this.start,
    this.end,
    this.location = '',
    this.startDate,
    this.endDate,
    this.reasons = const [],
    this.edited = false,
  });

  factory ClassDraft.fromRow(int id, ParsedRow row) => ClassDraft(
    id: id,
    course: row.course,
    title: row.title,
    section: row.section,
    component: row.component,
    days: row.days,
    start: row.start,
    end: row.end,
    location: row.location,
    startDate: row.startDate,
    endDate: row.endDate,
    reasons: row.needsReview ? row.reasons : const [],
  );

  final int id;
  final String course;
  final String title;
  final String section;
  final String component;

  /// Weekday numbers, 0 = Monday.
  final List<int> days;

  /// `HH:mm`.
  final String? start;
  final String? end;
  final String location;

  /// `YYYY-MM-DD`.
  final String? startDate;
  final String? endDate;

  /// Why the picture's reading was not sure of this class, in words for the student.
  final List<String> reasons;

  /// True once the student has looked at this class and changed it.
  final bool edited;

  /// The reading was not sure of this class and the student has not looked at it yet.
  bool get flagged => reasons.isNotEmpty && !edited;

  /// `XYZ 10 Lecture`.
  String get label => [course, component].where((s) => s.isNotEmpty).join(' ');

  /// `MoWeFr`.
  String get daysLabel => days.map((d) => dayCodes[d]).join();

  /// `2:40 PM–3:45 PM`, with a `?` for a time that was not read, or nothing if neither was.
  String get timeLabel {
    if (start == null && end == null) return '';
    return '${start == null ? '?' : clockFromHhmm(start!)}–${end == null ? '?' : clockFromHhmm(end!)}';
  }

  bool get hasDates => startDate != null && endDate != null;

  /// What stops this class being saved, in words for the student, or null if it can be saved.
  String? get problem {
    if (course.trim().isEmpty) return 'Enter the course, like CSE 130.';
    if (days.isEmpty) return 'Pick the days it meets.';
    if (start == null || end == null) return 'Pick a start and end time.';
    if (end!.compareTo(start!) <= 0) return 'The end time must be after the start time.';
    if (!hasDates) return 'Pick the first and last dates.';
    if (endDate!.compareTo(startDate!) < 0) return 'The last date is before the first.';
    if (_tidy(course).length > 40 ||
        _tidy(title).length > 80 ||
        _tidy(section).length > 10 ||
        _tidy(component).length > 30 ||
        _tidy(location).length > 80) {
      return 'Something here is too long to save. Shorten it.';
    }
    return null;
  }

  /// The class as it is saved. Only call this when [problem] is null.
  Meeting toMeeting() => Meeting(
    course: _tidy(course),
    title: _tidy(title),
    section: _tidy(section),
    component: _tidy(component),
    days: ([...days]..sort()),
    start: start!,
    end: end!,
    location: _tidy(location),
    startDate: startDate!,
    endDate: endDate!,
  );

  ClassDraft copyWith({
    String? course,
    String? component,
    List<int>? days,
    String? start,
    String? end,
    String? location,
    String? startDate,
    String? endDate,
    bool? edited,
  }) => ClassDraft(
    id: id,
    course: course ?? this.course,
    title: title,
    section: section,
    component: component ?? this.component,
    days: days ?? this.days,
    start: start ?? this.start,
    end: end ?? this.end,
    location: location ?? this.location,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    reasons: reasons,
    edited: edited ?? this.edited,
  );
}

/// What the server made of a room, for showing next to the class.
enum RoomState {
  /// The server is being asked.
  checking,

  /// A building, and the room is on its list or it has no list.
  found,

  /// A building the server knows, but not this room number in it.
  unlisted,

  /// Not a place the server knows.
  notFound,

  /// Online or to be announced: not a room to find.
  none,

  /// The server could not be asked.
  unchecked;

  /// The student should look at this room.
  bool get needsLook => this == unlisted || this == notFound;
}
