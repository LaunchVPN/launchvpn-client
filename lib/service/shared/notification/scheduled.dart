import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

/// A notification the system shows at [at], even while the App is closed.
final class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;
}

/// The notification permission and notifications set for later.
abstract interface class ScheduledNotifications {
  Future<bool> permitted();

  /// Asks the system and answers whether notifications are now allowed.
  /// After a refusal the system no longer asks and answers false at once.
  Future<bool> request();

  /// Opens the App's page in the system settings, where notifications are
  /// allowed after a refusal.
  Future<void> openSettings();

  Future<void> schedule(ScheduledNotification notification);

  Future<void> cancel(int id);

  /// Names the reminders channel Android lists in its settings. Elsewhere it
  /// does nothing.
  Future<void> nameChannel(String name);
}

/// The phone's notifications, through the plugin `NotificationService`
/// initializes. Scheduled ones are reminders: Android puts them in their own
/// channel and delivers them inexactly, without the exact alarm permission.
final class SystemNotifications implements ScheduledNotifications {
  static const _channel = '${Brand.androidId}.reminders';

  final _plugin = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  // The plugin resolves only the running platform's side; others are null.
  // Desktop builds, kept for upstream merges, are not offered reminders.
  @override
  Future<bool> permitted() async {
    if (_android case final android?) {
      return await android.areNotificationsEnabled() ?? false;
    }
    return (await _ios?.checkPermissions())?.isEnabled ?? false;
  }

  @override
  Future<bool> request() async {
    await _android?.requestNotificationsPermission();
    await _ios?.requestPermissions(alert: true, sound: true);
    return permitted();
  }

  @override
  Future<void> openSettings() => openAppSettings();

  @override
  Future<void> schedule(ScheduledNotification notification) =>
      _plugin.zonedSchedule(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        // An absolute moment, so UTC needs no time zone database.
        scheduledDate: tz.TZDateTime.from(notification.at.toUtc(), tz.UTC),
        // Apart from the VPN status channel, so muting one keeps the other.
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel,
            appLocalizationsNoContext().notificationChannelReminders,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  // Creating an existing channel again renames it.
  @override
  Future<void> nameChannel(String name) async => _android
      ?.createNotificationChannel(AndroidNotificationChannel(_channel, name));
}
