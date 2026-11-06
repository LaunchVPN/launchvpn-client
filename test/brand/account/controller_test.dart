import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/servers/subscription/model.dart';

import '../../support/fake_account_api.dart';

const _configLink = 'https://sub.launch.tel/abc';
final _link = Uri.parse(
  'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
);

void main() {
  late FakeAccountApi api;
  late AppDatabase db;
  late List<Uri> opened;
  late List<String> refreshed;
  late List<String> removed;
  late FakeBrowser browser;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = FakeAccountApi();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    opened = [];
    refreshed = [];
    removed = [];
    browser = FakeBrowser();
  });

  AccountService account() => accountServiceFor(
    api,
    removeSubscription: (url) async => removed.add(url),
    addSubscription: opened.add,
    browser: browser,
  );

  AccountController controllerFor(
    AccountService account, {
    ValueListenable<bool>? deviceLimit,
  }) {
    final controller = AccountController(
      account: account,
      subscriptions: SubscriptionLinkService(database: db),
      deviceLimit: deviceLimit ?? ValueNotifier(false),
      refreshSubscription: (row) async {
        refreshed.add(row.url);
        return const SubscriptionRefreshResult(
          status: SubscriptionUpdateResult.success,
        );
      },
    );
    addTearDown(controller.close);
    return controller;
  }

  Future<AccountService> signedIn({String? configLink = _configLink}) async {
    api.loginWith(access: 'a1', refresh: 'r1');
    api.subscription(configLink);
    final service = account();
    await service.email.login(email: 'ivan@proton.me', password: 'pw');
    api.requests.clear();
    opened.clear();
    return service;
  }

  Future<void> addRow(String url) => db.subscriptionDao.insertRow(
    SubscriptionCompanion.insert(
      name: 'LaunchVPN',
      url: url,
      timestamp: DateTime(2026),
      mode: Value(SubscriptionMode.providerManaged.name),
      // 14 December 2026 and 272.6 GB of an unlimited plan.
      expireTimestamp: const Value(1797206400),
      uploadBytes: const Value(2600000000),
      downloadBytes: const Value(270000000000),
      totalBytes: const Value(0),
      userInfoUpdatedAt: Value(DateTime(2026)),
    ),
  );

  test(
    'signed in, the tab shows the account and its devices, this one first',
    () async {
      final service = await signedIn();
      api.me(email: 'ivan@proton.me', telegramLinked: true);
      api.devices([
        {
          'hwid': 'pixel-8',
          'deviceModel': 'Pixel 8',
          'platform': 'Android',
          'osVersion': '16',
          'updatedAt': '2026-11-02T10:00:00Z',
        },
        {
          'hwid': 'device-hwid',
          'deviceModel': 'Pixel 9',
          'platform': 'Android',
          'osVersion': '16',
          'updatedAt': '2026-11-01T10:00:00Z',
        },
      ], max: 3);
      final controller = controllerFor(service);

      await controller.refresh();

      final state = controller.state;
      expect(state.signedIn, isTrue);
      expect(state.details?.email, 'ivan@proton.me');
      expect(state.details?.telegramLinked, isTrue);
      expect(state.devices?.max, 3);
      expect(
        [
          for (final device in state.devices!.items)
            (device.model, device.current),
        ],
        [('Pixel 9', true), ('Pixel 8', false)],
      );
      // The sign-in could not add the subscription, so the tab does.
      expect(opened, [_link]);
    },
  );

  test(
    'the subscription the device has is refreshed when the tab opens',
    () async {
      final service = await signedIn();
      await addRow(_configLink);
      final controller = controllerFor(service);

      await controller.refresh();

      expect(refreshed, [_configLink]);
      expect(opened, isEmpty);
      expect(controller.state.usage?.usedBytes, 272600000000);
      expect(
        controller.state.usage?.expiresAt,
        DateTime.utc(2026, 12, 14, 0, 0),
      );
    },
  );

  test('signed in without an active subscription, it shows as ended', () async {
    final service = await signedIn(configLink: null);
    final controller = controllerFor(service);

    await controller.refresh();

    expect(controller.state.inactive, isTrue);
    expect(opened, isEmpty);
  });

  test('a session restored without an active subscription shows as ended '
      'before the tab opens', () async {
    await signedIn(configLink: null);
    final restarted = account();
    await restarted.restore();

    final controller = controllerFor(restarted);
    await pumpEventQueue();

    expect(controller.state.inactive, isTrue);
  });

  test('an account whose email needs Telegram for the trial says so', () async {
    final service = await signedIn(configLink: null);
    api.trialOffer('telegram_required');
    final controller = controllerFor(service);

    await controller.refresh();

    expect(controller.state.trialWaitsOnTelegram, isTrue);
    expect(api.bodies('/api/app/trial'), isEmpty);
    expect(opened, isEmpty);
  });

  test('an account that can start the trial starts it', () async {
    final service = await signedIn(configLink: null);
    api.trialOffer('available');
    api.trialGrants(_configLink);
    final controller = controllerFor(service);

    await controller.refresh();

    expect(api.bodies('/api/app/trial'), hasLength(1));
    expect(opened, [_link]);
    expect(controller.state.inactive, isFalse);
    expect(controller.state.trialWaitsOnTelegram, isFalse);
  });

  test('an ended account claims nothing', () async {
    final service = await signedIn(configLink: null);
    api.trialOffer('unavailable');
    final controller = controllerFor(service);

    await controller.refresh();

    expect(api.bodies('/api/app/trial'), isEmpty);
    expect(controller.state.inactive, isTrue);
    expect(controller.state.trialWaitsOnTelegram, isFalse);
  });

  test('linking Telegram starts the trial it waited for', () async {
    final service = await signedIn(configLink: null);
    api.trialOffer('telegram_required');
    final controller = controllerFor(service);
    await controller.refresh();
    api.linkStartWith('https://app.test/api/auth/telegram/start?ticket=t1');
    api.refreshWith(access: 'a2', refresh: 'r2');
    api.exchangeWith(access: 'a3', refresh: 'r3');
    api.me(email: 'ivan@example.org', telegramLinked: true);
    api.trialOffer('available');
    api.trialGrants(_configLink);

    final outcome = controller.linkTelegram();
    await pumpEventQueue();
    service.telegram.browser.handleReturn(
      Uri.parse('launchvpn://auth?code=c1&mode=link'),
    );

    expect(await outcome, isA<TelegramLinked>());
    expect(opened, [_link]);
    expect(controller.state.inactive, isFalse);
    expect(controller.state.trialWaitsOnTelegram, isFalse);
  });

  test('linking Telegram while an earlier offer read is pending still '
      'starts the trial', () async {
    final service = await signedIn(configLink: null);
    final firstRead = Completer<void>();
    api.trialOffer('available');
    api.hold('GET /api/app/trial', firstRead.future);
    api.trialGrants(_configLink);
    api.linkStartWith('https://app.test/api/auth/telegram/start?ticket=t1');
    api.refreshWith(access: 'a2', refresh: 'r2');
    api.exchangeWith(access: 'a3', refresh: 'r3');
    api.me(email: 'ivan@example.org', telegramLinked: true);
    final controller = controllerFor(service);
    await pumpEventQueue();

    final outcome = controller.linkTelegram();
    await pumpEventQueue();
    service.telegram.browser.handleReturn(
      Uri.parse('launchvpn://auth?code=c1&mode=link'),
    );
    // The link has reloaded the account and asks for the offer again.
    await pumpEventQueue(times: 500);
    expect(api.requests.where((r) => r.path == '/api/me'), isNotEmpty);
    firstRead.complete();

    expect(await outcome, isA<TelegramLinked>());
    expect(api.bodies('/api/app/trial'), hasLength(1));
    expect(opened, [_link]);
  });

  test('from a link only, days and traffic come from the device', () async {
    await addRow('https://sub.launch.tel/from-bot');
    final controller = controllerFor(account());

    await controller.refresh();

    expect(controller.state.signedIn, isFalse);
    expect(controller.state.details, isNull);
    expect(controller.state.devices, isNull);
    expect(controller.state.usage?.usedBytes, 272600000000);
    expect(refreshed, ['https://sub.launch.tel/from-bot']);
    expect(api.requests, isEmpty);
  });

  test('the device limit is the one the panel sets for this user', () async {
    final service = await signedIn();
    api.subscription(_configLink, maxDevices: 5);
    api.devices([
      {'hwid': 'device-hwid'},
    ], max: 3);
    final controller = controllerFor(service);

    await controller.refresh();

    expect(controller.state.deviceLimit, 5);
  });

  test('without a limit for this user, the backend\'s own applies', () async {
    final service = await signedIn();
    api.devices([
      {'hwid': 'device-hwid'},
    ], max: 3);
    final controller = controllerFor(service);

    await controller.refresh();

    expect(controller.state.deviceLimit, 3);
  });

  test('while the panel refuses this device for the limit, the tab adds the '
      'subscription again only once a place is free', () async {
    final service = await signedIn();
    api.devices([
      {'hwid': 'pixel-8'},
      {'hwid': 'pixel-7'},
    ], max: 2);
    final controller = controllerFor(service, deviceLimit: ValueNotifier(true));

    await controller.refresh();
    await controller.refresh();
    expect(opened, isEmpty);

    await controller.removeDevice(controller.state.devices!.items.first);
    await controller.refresh();
    expect(opened, [_link]);
  });

  test('a removed device leaves the list at once', () async {
    final service = await signedIn();
    api.devices([
      {'hwid': 'device-hwid', 'deviceModel': 'Pixel 9'},
      {'hwid': 'pixel-8', 'deviceModel': 'Pixel 8'},
    ], max: 3);
    final controller = controllerFor(service);
    await controller.refresh();
    final other = controller.state.devices!.items.last;

    expect(await controller.removeDevice(other), isTrue);

    expect(
      [for (final device in controller.state.devices!.items) device.hwid],
      ['device-hwid'],
    );
    expect(
      api.requests
          .where((r) => r.path == '/api/devices/disconnect')
          .single
          .data,
      {'hwid': 'pixel-8'},
    );
  });

  test('a device the panel failed to remove stays listed', () async {
    final service = await signedIn();
    api.devices([
      {'hwid': 'device-hwid'},
      {'hwid': 'pixel-8'},
    ], max: 3);
    api.refuseDeviceRemoval();
    final controller = controllerFor(service);
    await controller.refresh();

    expect(
      await controller.removeDevice(controller.state.devices!.items.last),
      isFalse,
    );
    expect(controller.state.devices!.items, hasLength(2));
  });

  test('linking Telegram swaps in the merged account\'s subscription and '
      'account details', () async {
    final service = await signedIn();
    await addRow(_configLink);
    const telegramLink = 'https://sub.launch.tel/telegram';
    api.linkStartWith('https://app.test/api/auth/telegram/start?ticket=t1');
    api.refreshWith(access: 'a2', refresh: 'r2');
    api.exchangeWith(
      access: 'a3',
      refresh: 'r3',
      addedDays: 30,
      bringing: telegramLink,
    );
    api.me(email: 'ivan@proton.me', telegramLinked: true);
    final controller = controllerFor(service);

    final outcome = controller.linkTelegram();
    await pumpEventQueue();
    service.telegram.browser.handleReturn(
      Uri.parse('launchvpn://auth?code=c1&mode=link'),
    );

    expect(
      await outcome,
      isA<TelegramLinked>().having((o) => o.addedDays, 'addedDays', 30),
    );
    expect(removed, [_configLink]);
    expect(opened, [
      Uri.parse(
        'launchvpn://sub/add?url=${Uri.encodeQueryComponent(telegramLink)}',
      ),
    ]);
    expect(controller.state.details?.telegramLinked, isTrue);
    expect(controller.state.linkingTelegram, isFalse);
  });

  test('linking Telegram the system closed the App during completes once '
      'the tab is back, and tells it once', () async {
    final service = await signedIn();
    await addRow(_configLink);
    const telegramLink = 'https://sub.launch.tel/telegram';
    api.linkStartWith('https://app.test/api/auth/telegram/start?ticket=t1');
    api.refreshWith(access: 'a2', refresh: 'r2');
    api.exchangeWith(
      access: 'a3',
      refresh: 'r3',
      addedDays: 30,
      bringing: telegramLink,
    );
    api.me(email: 'ivan@proton.me', telegramLinked: true);
    unawaited(service.telegram.openLink());
    await pumpEventQueue();
    final restarted = account();
    await restarted.restore();
    final controller = controllerFor(restarted);

    restarted.telegram.browser.handleReturn(
      Uri.parse('launchvpn://auth?code=c1&mode=link'),
    );
    await pumpEventQueue(times: 50);

    expect(
      controller.state.resumedLink,
      isA<TelegramLinked>().having((o) => o.addedDays, 'addedDays', 30),
    );
    expect(opened, [
      Uri.parse(
        'launchvpn://sub/add?url=${Uri.encodeQueryComponent(telegramLink)}',
      ),
    ]);
    controller.resumedLinkShown();
    expect(controller.state.resumedLink, isNull);
  });

  test('an account subscription that changed replaces the device\'s '
      'one', () async {
    api.loginWith(access: 'a1', refresh: 'r1');
    api.subscription(_configLink);
    final service = accountServiceFor(
      api,
      addSubscription: opened.add,
      removeSubscription: (url) async {
        removed.add(url);
        final row = await SubscriptionLinkService(database: db).current();
        await db.subscriptionDao.deleteRow(row!.id);
      },
    );
    await service.email.login(email: 'ivan@proton.me', password: 'pw');
    await addRow(_configLink);
    opened.clear();
    const telegramLink = 'https://sub.launch.tel/telegram';
    api.subscription(telegramLink);
    final controller = controllerFor(service);

    await controller.refresh();

    expect(removed, [_configLink]);
    expect(opened, [
      Uri.parse(
        'launchvpn://sub/add?url=${Uri.encodeQueryComponent(telegramLink)}',
      ),
    ]);
  });

  group('a session that ends while the tab loads', () {
    test('a refresh outliving logout adds nothing', () async {
      final service = await signedIn();
      final devices = Completer<void>();
      api.hold('/api/devices', devices.future);
      final controller = controllerFor(service);

      final refresh = controller.refresh();
      await pumpEventQueue();
      await controller.logout();
      devices.complete();
      await refresh;

      expect(opened, isEmpty);
      expect(controller.state.devices, isNull);
    });

    test('the previous account\'s answers do not reach the next one', () async {
      final service = await signedIn();
      api.me(email: 'ivan@proton.me', telegramLinked: false);
      final first = Completer<void>();
      api.hold('/api/me', first.future);
      final controller = controllerFor(service);
      final stale = controller.refresh();
      await pumpEventQueue();
      await controller.logout();

      api.loginWith(access: 'a2', refresh: 'r2');
      api.me(email: 'olga@proton.me', telegramLinked: false);
      await service.email.login(email: 'olga@proton.me', password: 'pw');
      await pumpEventQueue();
      first.complete();
      await stale;

      expect(controller.state.details?.email, 'olga@proton.me');
    });

    test('linking Telegram shows no details the merged account did not '
        'load', () async {
      final service = await signedIn();
      api.me(email: 'ivan@proton.me', telegramLinked: false);
      api.devices([
        {'hwid': 'device-hwid'},
      ], max: 3);
      final controller = controllerFor(service);
      await controller.refresh();
      api.linkStartWith('https://app.test/api/auth/telegram/start?ticket=t1');
      api.refreshWith(access: 'a2', refresh: 'r2');
      api.exchangeWith(access: 'a3', refresh: 'r3');
      api.subscription('https://sub.launch.tel/telegram');
      api.refuse('/api/me', 502, 'bad_gateway');
      api.refuse('/api/devices', 502, 'bad_gateway');

      final outcome = controller.linkTelegram();
      await pumpEventQueue();
      service.telegram.browser.handleReturn(
        Uri.parse('launchvpn://auth?code=c1&mode=link'),
      );

      expect(await outcome, isA<TelegramLinked>());
      expect(controller.state.details, isNull);
      expect(controller.state.devices, isNull);
    });
  });

  test(
    'logout ends the session and removes the account subscription',
    () async {
      final service = await signedIn();
      final controller = controllerFor(service);

      await controller.logout();

      expect(service.session.signedIn.value, isFalse);
      expect(controller.state.signedIn, isFalse);
      expect(api.authorizations('/api/app/auth/logout'), ['Bearer a1']);
      expect(removed, [_configLink]);
      final restarted = account();
      await restarted.restore();
      expect(restarted.session.signedIn.value, isFalse);
    },
  );

  group('«Удалить аккаунт»', () {
    test('deletes the account', () async {
      final controller = controllerFor(await signedIn());

      expect(await controller.deleteAccount(), AccountDeletion.deleted);
      expect(controller.state.deletingAccount, isFalse);
    });

    test('a backend failure keeps the account', () async {
      final controller = controllerFor(await signedIn());
      api.refuse('/api/app/account/delete', 502, 'panel_failed');

      expect(await controller.deleteAccount(), AccountDeletion.failed);
      expect(controller.state.signedIn, isTrue);
    });

    test('a session already gone asks to sign in again, with the '
        'subscription the device kept', () async {
      final service = await signedIn();
      await addRow('https://sub.launch.tel/from-bot');
      final controller = controllerFor(service);
      await controller.refresh();
      api.rejectAccess('a1');
      api.refuseRefresh();

      expect(await controller.deleteAccount(), AccountDeletion.signInAgain);
      expect(controller.state.signedIn, isFalse);
      expect(
        controller.state.subscription?.url,
        'https://sub.launch.tel/from-bot',
      );
    });
  });
}
