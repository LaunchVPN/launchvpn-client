import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/servers/subscription/renewal_reminders.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../support/fake_notifications.dart';

int _epoch(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

void main() {
  late AppDatabase db;
  late FakeNotifications notifications;
  late DateTime now;
  late RenewalReminders reminders;
  late AppEventBus bus;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  setUp(() async {
    await SharedPreferencesAsync().clear();
    // Closing the bus would dispose the App's services.
    bus = AppEventBus();
    await bus.updateLanguageCode(LanguageCode.ru);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    notifications = FakeNotifications();
    now = DateTime(2026, 11, 3, 15);
    reminders = RenewalReminders(
      database: db,
      notifications: notifications,
      clock: () => now,
    );
  });

  Future<void> addSubscription({DateTime? expires}) =>
      db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'LaunchVPN',
          url: 'https://sub.example/a',
          timestamp: DateTime(2026),
          mode: Value(SubscriptionMode.providerManaged.name),
          expireTimestamp: Value(expires == null ? null : _epoch(expires)),
          userInfoUpdatedAt: Value(DateTime.utc(2026)),
        ),
      );

  test('reminds at noon three days and one day before the expiry', () async {
    await addSubscription(expires: DateTime(2026, 11, 20, 3));

    await reminders.update();

    expect(notifications.shown, [
      (DateTime(2026, 11, 17, 12), 'Подписка закончится через 3 дня'),
      (DateTime(2026, 11, 19, 12), 'Подписка закончится завтра'),
    ]);
    expect(notifications.pending.values.map((r) => r.body).toSet(), {
      'Продлите её, чтобы VPN не отключился.',
    });
  });

  test('speak the language the App shows', () async {
    await addSubscription(expires: DateTime(2026, 11, 20, 3));
    await bus.updateLanguageCode(LanguageCode.en);

    await reminders.update();

    expect(notifications.shown.map((r) => r.$2), [
      'Your subscription ends in 3 days',
      'Your subscription ends tomorrow',
    ]);
  });

  test(
    'rename their Android channel with the language, even when off',
    () async {
      await reminders.disable();
      await bus.updateLanguageCode(LanguageCode.en);

      await reminders.update();

      expect(notifications.channel, 'Reminders');
    },
  );

  test('leaves out a reminder whose time has passed', () async {
    now = DateTime(2026, 11, 17, 12, 1);
    await addSubscription(expires: DateTime(2026, 11, 20, 3));

    await reminders.update();

    expect(notifications.shown, [
      (DateTime(2026, 11, 19, 12), 'Подписка закончится завтра'),
    ]);
  });

  Future<void> setExpiry(DateTime? expires) async {
    final row = (await db.subscriptionDao.allRows).single;
    await db.subscriptionDao.updateRow(
      row.copyWith(
        expireTimestamp: Value(expires == null ? null : _epoch(expires)),
      ),
    );
  }

  test('a renewal moves the reminders to the new expiry', () async {
    now = DateTime(2026, 11, 18, 9);
    await addSubscription(expires: DateTime(2026, 11, 20, 3));
    await reminders.update();

    await setExpiry(DateTime(2026, 12, 20, 3));
    await reminders.update();

    expect(notifications.shown.map((r) => r.$1), [
      DateTime(2026, 12, 17, 12),
      DateTime(2026, 12, 19, 12),
    ]);
  });

  test(
    'a subscription without expiry or none at all gets no reminders',
    () async {
      await addSubscription(expires: DateTime(2026, 11, 20, 3));
      await reminders.update();

      await setExpiry(null);
      await reminders.update();
      expect(notifications.pending, isEmpty);

      await setExpiry(DateTime(2026, 11, 20, 3));
      await reminders.update();
      await db.subscriptionDao.deleteRow(
        (await db.subscriptionDao.allRows).single.id,
      );
      await reminders.update();
      expect(notifications.pending, isEmpty);
    },
  );

  test('are on by default, and turning them off removes them', () async {
    await addSubscription(expires: DateTime(2026, 11, 20, 3));
    expect(await reminders.active, isTrue);
    await reminders.update();

    await reminders.disable();

    expect(await reminders.active, isFalse);
    expect(notifications.pending, isEmpty);
    await reminders.update();
    expect(notifications.pending, isEmpty);
  });

  test('without notification permission none are set', () async {
    notifications.allowed = false;
    await addSubscription(expires: DateTime(2026, 11, 20, 3));

    await reminders.update();

    expect(await reminders.active, isFalse);
    expect(notifications.pending, isEmpty);
  });

  test('turning them on asks for the permission they lack', () async {
    await addSubscription(expires: DateTime(2026, 11, 20, 3));
    await reminders.disable();
    notifications.allowed = false;

    await reminders.enable();
    expect(await reminders.active, isFalse);
    expect(notifications.requests, 1);
    expect(notifications.pending, isEmpty);
    // The system no longer asks, so only its settings can allow them.
    expect(notifications.settingsOpened, 1);

    notifications.grantOnRequest = true;
    await reminders.enable();
    expect(await reminders.active, isTrue);
    expect(notifications.pending, hasLength(2));
    expect(notifications.settingsOpened, 1);
  });

  test('follow subscription loads and the return to the App', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    notifications.allowed = false;
    reminders.start();
    addTearDown(reminders.dispose);

    await addSubscription(expires: DateTime(2026, 11, 20, 3));
    await pumpEventQueue();
    expect(notifications.pending, isEmpty);

    // Notifications allowed in the system settings.
    notifications.allowed = true;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(notifications.pending, hasLength(2));

    await setExpiry(DateTime(2026, 12, 20, 3));
    await pumpEventQueue();
    expect(notifications.shown.first.$1, DateTime(2026, 12, 17, 12));
  });
}
