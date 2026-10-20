import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current time. Tests replace it to pin the day.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
