import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';

/// The term's first and last day, so the "add a class" form can start with them filled in.
final termProvider = FutureProvider<({String start, String end})?>((ref) async {
  try {
    final term = (await ref.read(apiClientProvider).getJson('/api/meta'))['term'];
    if (term is Map && term['start'] is String && term['end'] is String) {
      return (start: term['start'] as String, end: term['end'] as String);
    }
  } on Object {
    // no server yet, or it is asleep: the form just starts with empty dates
  }
  return null;
});
