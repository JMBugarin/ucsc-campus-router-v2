/// How far a note is from needing the student's attention.
enum IssueSeverity {
  info(1.0),
  note(0.97),
  check(0.8),
  missing(0.6);

  const IssueSeverity(this.factor);

  /// What a row's confidence is multiplied by for each issue of this kind.
  final double factor;
}

/// Something about a class read from a picture that the student may want to look at.
enum RowIssue {
  unsureText('Some of this was hard to read.', IssueSeverity.check),
  correctedText('Some characters were corrected.', IssueSeverity.note),
  guessedDays('The days may be wrong.', IssueSeverity.check),
  guessedTime('AM or PM was guessed.', IssueSeverity.check),
  guessedCourse('The course may be wrong.', IssueSeverity.check),
  splitText('Two columns were read as one.', IssueSeverity.note),
  noCourse('No course was found.', IssueSeverity.missing),
  noDays('No days were found.', IssueSeverity.missing),
  noTime('No time was found.', IssueSeverity.missing),
  noRoom('No room was found.', IssueSeverity.note),
  noDates('No dates were found.', IssueSeverity.info);

  const RowIssue(this.message, this.severity);

  final String message;
  final IssueSeverity severity;
}

/// A row with less confidence than this is flagged for the student to check.
const reviewThreshold = 0.85;

/// One class meeting read from a picture. Days are weekday numbers with 0 = Monday, times are `HH:mm`, dates
/// are `YYYY-MM-DD`; anything the picture did not show is empty or null.
class ParsedRow {
  const ParsedRow({
    required this.course,
    this.title = '',
    this.section = '',
    this.component = '',
    required this.days,
    this.start,
    this.end,
    this.location = '',
    this.startDate,
    this.endDate,
    required this.confidence,
    this.issues = const {},
  });

  final String course;
  final String title;
  final String section;
  final String component;
  final List<int> days;
  final String? start;
  final String? end;
  final String location;
  final String? startDate;
  final String? endDate;

  /// From 0 to 1: how sure the reading is, from how clearly the text was read and how much had to be repaired
  /// or guessed.
  final double confidence;
  final Set<RowIssue> issues;

  bool get needsReview => confidence < reviewThreshold;

  ParsedRow copyWith({List<int>? days, double? confidence, Set<RowIssue>? issues}) => ParsedRow(
    course: course,
    title: title,
    section: section,
    component: component,
    days: days ?? this.days,
    start: start,
    end: end,
    location: location,
    startDate: startDate,
    endDate: endDate,
    confidence: confidence ?? this.confidence,
    issues: issues ?? this.issues,
  );

  /// What is missing or wrong, for the student, worst first.
  List<String> get reasons => [
    for (final issue in (issues.toList()..sort((a, b) => b.severity.index.compareTo(a.severity.index))))
      if (issue.severity != IssueSeverity.info) issue.message,
  ];
}

/// Why nothing was found.
enum ReadProblem {
  /// The picture had no text in it.
  noText,

  /// The picture had text, but none of it looked like a class schedule.
  noClasses,
}

/// Everything read from one picture.
class ParsedSchedule {
  const ParsedSchedule({required this.rows, this.notes = const [], this.problem});

  final List<ParsedRow> rows;

  /// Things worth telling the student, such as a course that was skipped because it is dropped.
  final List<String> notes;
  final ReadProblem? problem;
}
