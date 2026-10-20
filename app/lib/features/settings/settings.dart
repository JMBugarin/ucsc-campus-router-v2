import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';

/// Set in `main()` once the stored settings have been loaded. Tests override it.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

const _hostedServerUrl = String.fromEnvironment('SERVER_URL', defaultValue: 'https://ucsc-campus-router.onrender.com');

/// The hosted server, or the `--dart-define=SERVER_URL=...` override. The web build (used for
/// development) is served by the server itself, so it uses its own address.
String get defaultServerUrl => kIsWeb ? Uri.base.origin : _hostedServerUrl;

class Settings {
  const Settings({
    this.serverUrl = '',
    this.useLocation = true,
    this.remindersOn = false,
    this.remindLeadMinutes = 5,
  });

  /// The server's address, or empty if none has been entered.
  final String serverUrl;

  /// Whether to use the phone's location for the walk to class.
  final bool useLocation;

  /// Whether to show "time to leave" notifications.
  final bool remindersOn;

  /// How many minutes before leaving to give a heads-up (0 for none).
  final int remindLeadMinutes;

  Settings copyWith({String? serverUrl, bool? useLocation, bool? remindersOn, int? remindLeadMinutes}) => Settings(
        serverUrl: serverUrl ?? this.serverUrl,
        useLocation: useLocation ?? this.useLocation,
        remindersOn: remindersOn ?? this.remindersOn,
        remindLeadMinutes: remindLeadMinutes ?? this.remindLeadMinutes,
      );
}

const _kServerUrl = 'server_url';
const _kUseLocation = 'use_location';
const _kRemindersOn = 'reminders_on';
const _kRemindLead = 'remind_lead';

class SettingsController extends Notifier<Settings> {
  late SharedPreferences _prefs;

  @override
  Settings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return Settings(
      serverUrl: _prefs.getString(_kServerUrl) ?? defaultServerUrl,
      useLocation: _prefs.getBool(_kUseLocation) ?? true,
      remindersOn: _prefs.getBool(_kRemindersOn) ?? false,
      remindLeadMinutes: _prefs.getInt(_kRemindLead) ?? 5,
    );
  }

  Future<void> setServerUrl(String url) async {
    state = state.copyWith(serverUrl: url);
    await _prefs.setString(_kServerUrl, url);
  }

  Future<void> setUseLocation(bool value) async {
    state = state.copyWith(useLocation: value);
    await _prefs.setBool(_kUseLocation, value);
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

final settingsProvider = NotifierProvider<SettingsController, Settings>(SettingsController.new);

/// The client for the server address in the settings. It is rebuilt when the address changes.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(baseUrl: ref.watch(settingsProvider.select((s) => s.serverUrl)));
  ref.onDispose(client.close);
  return client;
});

/// Pings the server so a sleeping host starts waking before the first real request. Tests replace it.
final serverWarmUpProvider = Provider<Future<void> Function()>((ref) => () => ref.read(apiClientProvider).warmUp());
