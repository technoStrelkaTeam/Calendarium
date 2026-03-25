import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();
  static const MethodChannel _timeZoneChannel = MethodChannel('local_timezone');
  static const MethodChannel _exactAlarmChannel = MethodChannel('exact_alarm_permission');

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    tz.initializeTimeZones();
    await _configureLocalTimeZone();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);
    await _requestPermissions();
    _initialized = true;
  }

  Future<void> scheduleForSubscriptions(List<Subscription> subscriptions) async {
    await init();
    await _plugin.cancelAll();
    final exactAllowed = await canScheduleExactAlarms();
    for (final subscription in subscriptions) {
      final scheduled = _buildReminderTime(subscription.nextBillingDate.subtract(Duration(days: 1)));
      if (scheduled == null) {
        continue;
      }
      final id = _notificationId(subscription);
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'subscription_reminders',
          'Subscription reminders',
          channelDescription: 'Reminders about upcoming subscription charges',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      );
      await _plugin.zonedSchedule(
        id,
        'Скоро списание',
        '${subscription.name} • ${subscription.price.toStringAsFixed(2)} RUB завтра',
        scheduled,
        details,
        androidScheduleMode: exactAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> showTestNotification() async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'subscription_reminders',
        'Subscription reminders',
        channelDescription: 'Reminders about upcoming subscription charges',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      999999,
      'Тестовое уведомление',
      'Если ты это видишь — уведомления работают',
      details,
    );

    final scheduled = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));
    final exactAllowed = await canScheduleExactAlarms();
    await _plugin.zonedSchedule(
      1000000,
      'Тестовое уведомление (10с)',
      'Проверка отложенного уведомления',
      scheduled,
      details,
      androidScheduleMode: exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<bool> areNotificationsEnabled() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await android?.areNotificationsEnabled();
    return enabled ?? true;
  }

  Future<bool> canScheduleExactAlarms() async {
    try {
      final result =
          await _exactAlarmChannel.invokeMethod<bool>('canScheduleExactAlarms');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestExactAlarmPermission() async {
    try {
      final result = await _exactAlarmChannel
          .invokeMethod<bool>('requestExactAlarmPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  tz.TZDateTime? _buildReminderTime(DateTime nextBillingDate) {
    final now = tz.TZDateTime.now(tz.local);
    final base = DateTime(nextBillingDate.year, nextBillingDate.month, nextBillingDate.day)
        .subtract(const Duration(days: 1))
        .add(const Duration(hours: 13));
    final scheduled = tz.TZDateTime.from(base, tz.local);
    if (scheduled.isBefore(now)) {
      return null;
    }
    return scheduled;
  }

  int _notificationId(Subscription subscription) {
    if (subscription.id != null) {
      return subscription.id!;
    }
    final raw = '${subscription.name}-${subscription.nextBillingDate.toIso8601String()}';
    return _hashToInt(raw);
  }

  int _hashToInt(String value) {
    final bytes = utf8.encode(value);
    var hash = 0;
    for (final byte in bytes) {
      hash = (hash * 31 + byte) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> _requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _configureLocalTimeZone() async {
    try {
      final localTimeZone =
          await _timeZoneChannel.invokeMethod<String>('getLocalTimezone');
      if (localTimeZone != null && localTimeZone.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(localTimeZone));
        return;
      }
    } catch (_) {
      // Fallback to UTC if we cannot resolve the device timezone.
    }
    tz.setLocalLocation(tz.getLocation('UTC'));
  }
}
