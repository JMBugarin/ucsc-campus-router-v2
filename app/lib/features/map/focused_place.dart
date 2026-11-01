import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../search/place.dart';

/// A place another tab wants the map to show (for example a class on Today). The map takes it and clears it.
class FocusedPlace extends Notifier<Place?> {
  @override
  Place? build() => null;

  void focus(Place place) => state = place;

  void clear() => state = null;
}

final focusedPlaceProvider = NotifierProvider<FocusedPlace, Place?>(
  FocusedPlace.new,
);
