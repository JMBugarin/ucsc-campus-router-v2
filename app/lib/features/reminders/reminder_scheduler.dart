import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../today/today_models.dart';

/// Shows or schedules "time to leave" notifications. The real one talks to Android; tests use a fake.
abstract class ReminderScheduler {
  /// Asks for permission to show notifications (and to be on time). True if notifications are allowed.
  Future<bool> requestPermission();

  /// Shows [reminder] right now.
  Future<void> show(Reminder reminder);

  /// Has the phone show [reminder] at [at], even if the app is closed by then.
  Future<void> schedule(Reminder reminder, DateTime at);

  Future<void> cancel(String key);
}

/// A number for the phone that is the same every run (Dart's String.hashCode is not).
int notificationId(String key) {
  var hash = 0x811c9dc5; // FNV-1a
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

class LocalNotificationScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'leave_now',
      'Time to leave',
      channelDescription: 'Tells you when to leave for your next class',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> _init() => _ready ??= _plugin
      .initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')))
      .then((_) {});

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async {
    await _init();
    final allowed = await _android?.requestNotificationsPermission() ?? false;
    // Exact alarms keep "leave now" on time. Android may open its settings page for this; if it is
    // refused, reminders still work but can arrive a few minutes late.
    if (allowed && await _android?.canScheduleExactNotifications() == false) {
      await _android?.requestExactAlarmsPermission();
    }
    return allowed;
  }

  @override
  Future<void> show(Reminder reminder) async {
    await _init();
    await _plugin.show(
      id: notificationId(reminder.key),
      title: reminder.title,
      body: reminder.body,
      notificationDetails: _details,
    );
  }

  @override
  Future<void> schedule(Reminder reminder, DateTime at) async {
    await _init();
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    await _plugin.zonedSchedule(
      id: notificationId(reminder.key),
      title: reminder.title,
      body: reminder.body,
      // UTC is a fixed point in time, so no time zone database is needed.
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(String key) async {
    await _init();
    await _plugin.cancel(id: notificationId(key));
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) => LocalNotificationScheduler());
