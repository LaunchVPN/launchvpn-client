import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
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
    browser: browser,
  );

  AccountController controllerFor(AccountService account) {
    final controller = AccountController(
      account: account,
      openLink: opened.add,
      database: db,
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
    await service.login(email: 'ivan@proton.me', password: 'pw');
    api.requests.clear();
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
      expect(state.profile?.email, 'ivan@proton.me');
      expect(state.profile?.telegramLinked, isTrue);
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

  test('from a link only, days and traffic come from the device', () async {
    await addRow('https://sub.launch.tel/from-bot');
    final controller = controllerFor(account());

    await controller.refresh();

    expect(controller.state.signedIn, isFalse);
    expect(controller.state.profile, isNull);
    expect(controller.state.devices, isNull);
    expect(controller.state.usage?.usedBytes, 272600000000);
    expect(refreshed, ['https://sub.launch.tel/from-bot']);
    expect(api.requests, isEmpty);
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
      'profile', () async {
    final service = await signedIn();
    await addRow(_configLink);
    const telegramLink = 'https://sub.launch.tel/telegram';
    api.linkStartWith('https://app.test/api/auth/telegram/start?ticket=t1');
    api.refreshWith(access: 'a2', refresh: 'r2');
    api.exchangeWith(access: 'a3', refresh: 'r3', addedDays: 30);
    api.subscription(telegramLink);
    api.me(email: 'ivan@proton.me', telegramLinked: true);
    final controller = controllerFor(service);

    final outcome = controller.linkTelegram();
    await pumpEventQueue();
    service.telegram.handleReturn(
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
    expect(controller.state.profile?.telegramLinked, isTrue);
    expect(controller.state.linkingTelegram, isFalse);
  });

  test(
    'logout ends the session and removes the account subscription',
    () async {
      final service = await signedIn();
      final controller = controllerFor(service);

      await controller.logout();

      expect(service.signedIn.value, isFalse);
      expect(controller.state.signedIn, isFalse);
      expect(api.authorizations('/api/app/auth/logout'), ['Bearer a1']);
      expect(removed, [_configLink]);
      final restarted = account();
      await restarted.restore();
      expect(restarted.signedIn.value, isFalse);
    },
  );
}
