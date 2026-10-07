import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../location/location_service.dart';
import '../schedule/meeting.dart';
import '../settings/settings.dart';
import 'today_models.dart';

abstract class TodayRepository {
  /// Asks the server where the student is in their day.
  ///
  /// [here] is where they are (the walk starts there); [remindLeadMinutes] and [reminded] let the
  /// server plan "time to leave" reminders and skip ones already shown.
  Future<Analysis> today({
    required List<Meeting> meetings,
    GeoPoint? here,
    int remindLeadMinutes = 5,
    List<String> reminded = const [],
  });
}

class ApiTodayRepository implements TodayRepository {
  ApiTodayRepository(this._api);

  final ApiClient _api;

  @override
  Future<Analysis> today({
    required List<Meeting> meetings,
    GeoPoint? here,
    int remindLeadMinutes = 5,
    List<String> reminded = const [],
  }) async {
    final json = await _api.postJson('/api/today', {
      'meetings': [for (final m in meetings) m.toJson()],
      if (here != null) 'here': [here.lat, here.lon],
      'remind_lead': remindLeadMinutes,
      'reminded': reminded,
    });
    return Analysis.fromJson(json);
  }
}

final todayRepositoryProvider = Provider<TodayRepository>((ref) => ApiTodayRepository(ref.watch(apiClientProvider)));
