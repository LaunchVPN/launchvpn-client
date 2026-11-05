import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/brand/account/page.dart';
import 'package:onexray/brand/app.dart';
import 'package:onexray/brand/router.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/distribution.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/shared/share/service.dart';

import '../../support/fake_account_api.dart';

void main() {
  late FakeAccountApi api;
  late AccountService account;
  late List<String> removed;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = FakeAccountApi();
    removed = [];
    account = accountServiceFor(
      api,
      removeSubscription: (url) async => removed.add(url),
    );
  });

  /// Signed in on a Russian phone, on «Аккаунт», with this device and a
  /// Pixel 8 on the subscription.
  Future<void> pumpAccount(
    WidgetTester tester, {
    AppDistribution distribution = AppDistribution.store,
  }) async {
    api.loginWith(access: 'a1', refresh: 'r1');
    api.subscription('https://sub.launch.tel/abc');
    api.me(email: 'ivan@proton.me', telegramLinked: false);
    api.devices([
      {'hwid': 'device-hwid', 'deviceModel': 'Pixel 9', 'platform': 'Android'},
      {
        'hwid': 'pixel-8',
        'deviceModel': 'Pixel 8',
        'platform': 'Android',
        'osVersion': '16',
      },
    ], max: 3);
    await tester.runAsync(
      () => account.login(email: 'ivan@proton.me', password: 'pw'),
    );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final controller = AccountController(
      account: account,
      openLink: (_) {},
      database: db,
      refreshSubscription: (_) async => const SubscriptionRefreshResult(
        status: SubscriptionUpdateResult.success,
      ),
    );
    addTearDown(controller.close);
    final links = StreamController<Uri>.broadcast(sync: true);
    final share = ShareService.forTesting(
      appLinks: links.stream,
      receiveWidgetUri: (_) => false,
    );
    addTearDown(() async {
      share.dispose();
      await links.close();
    });
    final router = createBrandRouter(
      home: const Text('home-body'),
      settings: const Text('settings-body'),
      accountTab: AccountPage(
        controller: controller,
        account: account,
        openLink: (_) {},
        distribution: distribution,
      ),
      account: account,
      watchSubscription: () => Stream.value(false),
      shareService: share,
      initializeServices: (_) => share.init(),
      openLink: (_, _) async {},
    );
    addTearDown(router.dispose);
    tester.platformDispatcher
      ..localeTestValue = const Locale('ru')
      ..localesTestValue = const [Locale('ru')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(BrandApp(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Аккаунт'));
    await settle(tester);
  }

  testWidgets('the store build shows the account without a renewal', (
    tester,
  ) async {
    await pumpAccount(tester);
    expect(find.text('ivan@proton.me'), findsOneWidget);
    expect(find.text('Вход по email'), findsOneWidget);
    expect(find.text('Продлить подписку'), findsNothing);
  });

  testWidgets('the APK build renews on the site', (tester) async {
    await pumpAccount(tester, distribution: AppDistribution.apk);

    expect(find.text('Продлить подписку'), findsOneWidget);
  });

  testWidgets('another device is removed from its sheet', (tester) async {
    await pumpAccount(tester);
    expect(find.text('УСТРОЙСТВА · 2 ИЗ 3'), findsOneWidget);
    expect(find.text('Android · это устройство'), findsOneWidget);

    // This device has no sheet.
    await tester.tap(find.text('Pixel 9'));
    await settle(tester);
    expect(find.text('Удалить устройство'), findsNothing);

    await tester.tap(find.text('Pixel 8'));
    await settle(tester);
    expect(
      find.textContaining('После удаления устройство потеряет доступ к VPN'),
      findsOneWidget,
    );
    await tester.tap(find.text('Удалить устройство'));
    await settle(tester);

    expect(find.text('Pixel 8 удалён, место освободилось'), findsOneWidget);
    expect(find.text('УСТРОЙСТВА · 1 ИЗ 3'), findsOneWidget);
    expect(find.text('Pixel 8'), findsNothing);
  });

  testWidgets('«Выйти» confirmed in its sheet leads to «Вход»', (tester) async {
    await pumpAccount(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('account-logout')));
    await tester.tap(find.byKey(const ValueKey('account-logout')));
    await settle(tester);
    expect(find.text('Выйти из аккаунта?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Выйти'));
    await settle(tester);

    expect(find.text('Интернет\nбез границ'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(removed, ['https://sub.launch.tel/abc']);
  });
}

/// Lets the in-memory database and the fake backend answer, then the frames
/// settle.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue(times: 20));
  await tester.pumpAndSettle();
}
