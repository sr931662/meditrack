import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../offline/reminder_planner.dart';

/// Schedules medication reminders on the device with the Android alarm manager, so they fire with no
/// network. Honest limits (see docs/OFFLINE_AND_ANDROID.md): OEM battery managers and Doze can delay
/// alarms; exact alarms need the user to allow "Alarms & reminders"; the schedule is rebuilt on app
/// start, after sync, and on device reboot (plugin boot receiver), but not by a background task.
class ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  void Function(String payload)? onTap;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null) onTap?.call(p);
      },
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> requestPermissions() async {
    await init();
    final notifications = await _android?.requestNotificationsPermission() ?? false;
    if (await _android?.canScheduleExactNotifications() != true) await _android?.requestExactAlarmsPermission();
    return notifications;
  }

  Future<bool> get exactAlarmsAllowed async => await _android?.canScheduleExactNotifications() ?? false;

  /// Replace everything pending with [plans]. Idempotent: ids are derived from schedule + time.
  Future<int> apply(List<ReminderPlan> plans) async {
    await init();
    await _plugin.cancelAll();
    final mode = await exactAlarmsAllowed ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'medication_reminders',
        'Medication reminders',
        channelDescription: 'Reminders to take your medicine',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
      ),
    );
    for (final p in plans) {
      await _plugin.zonedSchedule(
        id: p.id,
        scheduledDate: tz.TZDateTime.from(p.atUtc, tz.UTC),
        notificationDetails: details,
        androidScheduleMode: mode,
        title: p.title,
        body: p.body,
        payload: p.payload,
      );
    }
    return plans.length;
  }

  /// A one-off reminder, used for "remind me again" so it works without a connection.
  Future<void> scheduleOneOff({required int id, required DateTime atUtc, required String title, required String body, String? payload}) async {
    await init();
    final mode = await exactAlarmsAllowed ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(atUtc, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('medication_reminders', 'Medication reminders', importance: Importance.max, priority: Priority.high),
      ),
      androidScheduleMode: mode,
      title: title,
      body: body,
      payload: payload,
    );
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
