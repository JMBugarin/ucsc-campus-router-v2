/// One academic term: its first and last day of instruction and the no-class days inside it.
class Term {
  const Term({required this.name, required this.start, required this.end, this.holidays = const []});

  final String name;
  final String start;
  final String end;
  final List<String> holidays;

  factory Term.fromJson(Map<String, dynamic> json) => Term(
        name: (json['name'] as String?) ?? '',
        start: json['start'] as String,
        end: json['end'] as String,
        holidays: [for (final h in (json['holidays'] as List? ?? const [])) h as String],
      );
}

List<Term> termsFromJson(Map<String, dynamic> json) {
  final terms = [for (final t in (json['terms'] as List? ?? const [])) Term.fromJson(t as Map<String, dynamic>)];
  return terms..sort((a, b) => a.start.compareTo(b.start));
}

/// The term containing [iso] (a `YYYY-MM-DD` date); otherwise the next one to start, otherwise the last.
Term? termFor(List<Term> terms, String iso) {
  if (terms.isEmpty) return null;
  for (final t in terms) {
    if (t.start.compareTo(iso) <= 0 && iso.compareTo(t.end) <= 0) return t;
  }
  for (final t in terms) {
    if (t.start.compareTo(iso) > 0) return t;
  }
  return terms.last;
}

Set<String> holidaysOf(List<Term> terms) => {for (final t in terms) ...t.holidays};
