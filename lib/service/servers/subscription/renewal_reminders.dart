import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/shared/notification/scheduled.dart';

/// «Напоминать о продлении»: local notifications at noon three days and one
/// day before the expiry date from the subscription headers. They follow the
/// stored subscription, so a renewal moves them and no expiry removes them.
/// They speak the App's language as of the last [update].
final class RenewalReminders {
  RenewalReminders({
    required this._notifications,
    this._database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static final instance = RenewalReminders(
    notifications: SystemNotifications(),
  );

  // Construction touches no storage, so stopping services that never started
  // opens nothing. The database opens on first use.
  AppDatabase? _database;
  AppDatabase get _db => _database ??= AppDatabase();
  final ScheduledNotifications _notifications;
  final DateTime Function() _clock;
  StreamSubscription<DateTime?>? _expiry;
  AppLifecycleListener? _lifecycle;
  Future<void> _updates = Future.value();

  /// Notification ids and how many days before the expiry date each reminder
  /// comes. Id 0 belongs to the tray's notifications.
  static final _slots = [
    (id: 1, days: 3, title: (AppLocalizations l) => l.renewalReminderThreeDays),
    (id: 2, days: 1, title: (AppLocalizations l) => l.renewalReminderTomorrow),
  ];

  /// Follows the stored expiry, and the return to the App, where the person
  /// may have allowed notifications in the system settings.
  void start() {
    _expiry ??= _db.subscriptionDao.allRowsStream
        .map(_expiresAt)
        .distinct()
        .listen(
          (_) => unawaited(update()),
          onError: (Object error) => ygLogger(
            'watch subscription expiry failed (${error.runtimeType})',
          ),
        );
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(update()));
  }

  Future<void> dispose() async {
    _lifecycle?.dispose();
    _lifecycle = null;
    await _expiry?.cancel();
    _expiry = null;
  }

  /// What the switch shows: reminders work only while the setting is on and
  /// the system allows notifications.
  Future<bool> get active async =>
      await PreferencesKey().readRenewalReminders() &&
      await _notifications.permitted();

  /// A refusal opens the system settings, the only place left once the system
  /// stops asking; the return to the App sets the reminders.
  Future<void> enable() async {
    await PreferencesKey().saveRenewalReminders(true);
    if (!await _notifications.permitted() && !await _notifications.request()) {
      await _notifications.openSettings();
      return;
    }
    await update();
  }

  Future<void> disable() async {
    await PreferencesKey().saveRenewalReminders(false);
    await update();
  }

  /// Replaces the pending reminders with those the stored expiry calls for.
  /// Updates run one at a time, so an older one cannot outlive a newer one.
  Future<void> update() => _updates = _updates.then((_) async {
    try {
      await _replace();
    } catch (error) {
      ygLogger('update renewal reminders failed (${error.runtimeType})');
    }
  });

  Future<void> _replace() async {
    for (final slot in _slots) {
      await _notifications.cancel(slot.id);
    }
    if (!await active) return;
    final expiresAt = _expiresAt(await _db.subscriptionDao.allRows);
    if (expiresAt == null) return;
    final l = appLocalizationsNoContext();
    final end = expiresAt.toLocal();
    final now = _clock();
    for (final (:id, :days, :title) in _slots) {
      final at = DateTime(end.year, end.month, end.day - days, 12);
      if (!at.isAfter(now)) continue;
      await _notifications.schedule(
        ScheduledNotification(
          id: id,
          at: at,
          title: title(l),
          body: l.renewalReminderBody,
        ),
      );
    }
  }

  /// The App uses the last subscription, as Home does.
  static DateTime? _expiresAt(List<SubscriptionData> rows) {
    final row = rows.lastOrNull;
    return row == null
        ? null
        : SubscriptionUserInfo.fromSubscription(row)?.expiresAt;
  }
}
