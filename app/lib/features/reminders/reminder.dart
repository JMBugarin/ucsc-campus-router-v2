/// A "class starts soon" notification to show or schedule.
class Reminder {
  const Reminder({
    required this.stage,
    required this.key,
    required this.inSeconds,
    required this.title,
    required this.body,
  });

  final String stage;

  /// Identifies this reminder so it is never shown twice.
  final String key;
  final double inSeconds;
  final String title;
  final String body;
}
