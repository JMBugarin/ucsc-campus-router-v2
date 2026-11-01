import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../campus/campus_data.dart';
import '../../campus/terms.dart';
import '../../core/clock.dart';
import '../../core/pacific.dart';

/// The current term's first and last day, so the "add a class" form can start with them filled in.
final termProvider = FutureProvider<({String start, String end})?>((ref) async {
  final terms = await ref.watch(termsProvider.future);
  final term = termFor(terms, isoDate(pacificTime(ref.read(clockProvider)())));
  return term == null ? null : (start: term.start, end: term.end);
});
