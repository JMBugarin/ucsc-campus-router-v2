import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';

const _kHome = 'home_place';

/// The dorm or apartment someone saved as home (its id in `housing.json`), kept on this phone only.
class HomePlace extends Notifier<String?> {
  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_kHome);

  Future<void> set(String? id) async {
    state = id;
    final prefs = ref.read(sharedPreferencesProvider);
    if (id == null) {
      await prefs.remove(_kHome);
    } else {
      await prefs.setString(_kHome, id);
    }
  }
}

final homePlaceProvider = NotifierProvider<HomePlace, String?>(HomePlace.new);
