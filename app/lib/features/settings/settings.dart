import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Set in `main()` once the stored settings have been loaded. Tests override it.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

class Settings {
  const Settings({this.remindersOn = false, this.remindLeadMinutes = 10});

  /// Whether to show a notification before each class.
  final bool remindersOn;

  /// How many minutes before a class starts the notification comes (0 for at the start).
  final int remindLeadMinutes;

  Settings copyWith({bool? remindersOn, int? remindLeadMinutes}) => Settings(
    remindersOn: remindersOn ?? this.remindersOn,
    remindLeadMinutes: remindLeadMinutes ?? this.remindLeadMinutes,
  );
}

const _kRemindersOn = 'reminders_on';
const _kRemindLead = 'remind_lead_v2';

class SettingsController extends Notifier<Settings> {
  late SharedPreferences _prefs;

  @override
  Settings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return Settings(
      remindersOn: _prefs.getBool(_kRemindersOn) ?? false,
      remindLeadMinutes: _prefs.getInt(_kRemindLead) ?? 10,
    );
  }

  Future<void> setRemindersOn(bool value) async {
    state = state.copyWith(remindersOn: value);
    await _prefs.setBool(_kRemindersOn, value);
  }

  Future<void> setRemindLead(int minutes) async {
    state = state.copyWith(remindLeadMinutes: minutes);
    await _prefs.setInt(_kRemindLead, minutes);
  }
}

final settingsProvider = NotifierProvider<SettingsController, Settings>(
  SettingsController.new,
);
