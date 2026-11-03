import 'dart:async';

import 'package:onexray/service/shared/notification/scheduled.dart';

/// The phone's notifications: what is pending and what the person allows.
final class FakeNotifications implements ScheduledNotifications {
  final pending = <int, ScheduledNotification>{};
  bool allowed = true;
  bool grantOnRequest = false;
  int requests = 0;
  int settingsOpened = 0;

  /// While set, the system prompt stays open until it completes.
  Completer<void>? prompt;

  @override
  Future<bool> permitted() async => allowed;

  @override
  Future<bool> request() async {
    requests++;
    await prompt?.future;
    if (grantOnRequest) allowed = true;
    return allowed;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> schedule(ScheduledNotification notification) async =>
      pending[notification.id] = notification;

  @override
  Future<void> cancel(int id) async => pending.remove(id);

  /// Time and title of each pending notification, earliest first.
  List<(DateTime, String)> get shown =>
      [for (final n in pending.values) (n.at, n.title)]
        ..sort((a, b) => a.$1.compareTo(b.$1));
}
