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
  late FakeBrowser browser;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = FakeAccountApi();
    removed = [];
    browser = FakeBrowser();
    account = accountServiceFor(
      api,
      removeSubscription: (url) async => removed.add(url),
      browser: browser,
    );
  });

  /// Signed in on a Russian phone, on «Аккаунт», with this device and a
  /// Pixel 8 on the subscription. Not [signedIn], a subscription from a link
  /// keeps the tabs.
  Future<void> pumpAccount(
    WidgetTester tester, {
    AppDistribution distribution = AppDistribution.store,
    bool signedIn = true,
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
    if (signedIn) {
      await tester.runAsync(
        () => account.login(email: 'ivan@proton.me', password: 'pw'),
      );
    }
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
      watchSubscription: () => Stream.value(!signedIn),
      shareService: share,
      initializeServices: (_) => share.init(),
      openLink: (_, _) async {},
    );
    addTearDown(router.dispose);
    tester.platformDispatcher
      ..localeTestValue = const Locale('ru')
      ..localesTestValue = const [Locale('ru')]
      // A still backdrop on «Вход», so leaving the account can settle.
      ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
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

  group('«Привязать Telegram»', () {
    /// Taps the row; the browser opens and comes back with a link code.
    Future<void> linkAndReturn(WidgetTester tester) async {
      api.linkStartWith('https://app.test/api/auth/telegram/start?ticket=t1');
      api.refreshWith(access: 'a2', refresh: 'r2');
      await tester.ensureVisible(find.text('Привязать Telegram'));
      await tester.tap(find.text('Привязать Telegram'));
      await settle(tester);
      expect(browser.opened, hasLength(1));
      account.telegram.handleReturn(
        Uri.parse('launchvpn://auth?code=c1&mode=link'),
      );
      await settle(tester);
    }

    for (final (days, message) in [
      (30, 'Telegram привязан, 30 дней добавлены'),
      (0, 'Telegram привязан'),
    ]) {
      testWidgets('linking with $days days added says so and hides the row', (
        tester,
      ) async {
        await pumpAccount(tester);
        expect(find.text('Дни из бота добавятся к подписке'), findsOneWidget);
        api.exchangeWith(access: 'a3', refresh: 'r3', addedDays: days);
        api.me(email: 'ivan@proton.me', telegramLinked: true);

        await linkAndReturn(tester);

        // The email row's subtitle says it too.
        expect(find.text(message), findsNWidgets(days == 0 ? 2 : 1));
        expect(find.text('Telegram привязан'), findsWidgets);
        expect(find.text('Привязать Telegram'), findsNothing);
        expect(find.text('Вход по email'), findsNothing);
      });
    }

    testWidgets('a Telegram taken by another email account explains it in a '
        'sheet', (tester) async {
      await pumpAccount(tester);
      api.refuse('/api/app/auth/exchange', 409, 'telegram_taken');

      await linkAndReturn(tester);

      expect(find.text('Этот Telegram уже занят'), findsOneWidget);
      expect(
        find.text(
          'Он привязан к другому аккаунту с email. Чтобы увидеть его '
          'подписку, выйдите и войдите по тому email.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Понятно'));
      await settle(tester);
      expect(find.text('Этот Telegram уже занят'), findsNothing);
      expect(find.text('Привязать Telegram'), findsOneWidget);
    });
  });

  testWidgets('«Выйти» confirmed in its sheet leads to «Вход»', (tester) async {
    await pumpAccount(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('account-logout')));
    await tester.tap(find.byKey(const ValueKey('account-logout')));
    await settle(tester);
    expect(find.text('Выйти из аккаунта?'), findsOneWidget);
    expect(find.text('Войдите снова, чтобы подключиться.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Выйти'));
    await settle(tester);

    expect(find.text('Интернет\nбез границ'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(removed, ['https://sub.launch.tel/abc']);
  });

  group('«Удалить аккаунт»', () {
    /// Taps the last row and confirms in its sheet.
    Future<void> deleteAndConfirm(WidgetTester tester) async {
      final row = find.byKey(const ValueKey('account-delete'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await settle(tester);
      expect(find.text('Удалить аккаунт?'), findsOneWidget);
      expect(
        find.text(
          'Подписка и оставшиеся дни пропадут, в том числе полученные в '
          'боте. Отменить удаление нельзя.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить аккаунт'));
      await settle(tester);
    }

    testWidgets('confirmed, deletes the account and leads to «Вход»', (
      tester,
    ) async {
      await pumpAccount(tester);

      await deleteAndConfirm(tester);

      expect(api.bodies('/api/app/account/delete'), hasLength(1));
      expect(find.text('Интернет\nбез границ'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(removed, ['https://sub.launch.tel/abc']);
    });

    testWidgets('the backend failing keeps the person signed in and says so', (
      tester,
    ) async {
      await pumpAccount(tester);
      api.refuse('/api/app/account/delete', 502, 'panel_failed');

      await deleteAndConfirm(tester);

      expect(
        find.text('Не получилось удалить аккаунт. Попробуйте ещё раз'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const ValueKey('account-delete')), findsOneWidget);
      expect(removed, isEmpty);
    });

    testWidgets('is not offered without an account', (tester) async {
      await pumpAccount(tester, signedIn: false);

      expect(find.text('Войти'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-delete')), findsNothing);
    });
  });
}

/// Lets the in-memory database and the fake backend answer, then the frames
/// settle.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue(times: 20));
  await tester.pumpAndSettle();
}
