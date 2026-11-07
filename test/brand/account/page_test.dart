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
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/shared/share/service.dart';

import '../../support/fake_account_api.dart';
import '../../support/fake_url_launcher.dart';

void main() {
  late FakeAccountApi api;
  late AccountService account;
  late List<String> removed;
  late FakeBrowser browser;
  late StreamController<Uri> links;

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
  /// keeps the tabs; [linkSubscription] puts one on the device. Not
  /// [accountActive], the account's subscription ended after the sign-in.
  Future<void> pumpAccount(
    WidgetTester tester, {
    AppDistribution distribution = AppDistribution.store,
    bool signedIn = true,
    String? linkSubscription,
    bool telegramOnly = false,
    bool openAccount = true,
    bool accountActive = true,
    bool detailsLoad = true,
  }) async {
    api.loginWith(access: 'a1', refresh: 'r1');
    api.subscription('https://sub.launch.tel/abc', maxDevices: 5);
    api.me(
      email: telegramOnly ? null : 'ivan@proton.me',
      telegramLinked: telegramOnly,
    );
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
        () => account.email.login(email: 'ivan@proton.me', password: 'pw'),
      );
    }
    if (!accountActive) api.subscription(null);
    if (!detailsLoad) api.refuse('/api/me', 500, 'server_error');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    if (linkSubscription != null) {
      await tester.runAsync(
        () => db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: 'LaunchVPN',
            url: linkSubscription,
            timestamp: DateTime(2026),
          ),
        ),
      );
    }
    final controller = AccountController(
      account: account,
      subscriptions: SubscriptionLinkService(database: db),
      refreshSubscription: (_) async => const SubscriptionRefreshResult(
        status: SubscriptionUpdateResult.success,
      ),
    );
    addTearDown(controller.close);
    links = StreamController<Uri>.broadcast(sync: true);
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
        distribution: distribution,
      ),
      account: account,
      watchSubscription: () =>
          Stream.value(!signedIn || linkSubscription != null),
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
    // A Pixel's screen, so the whole card fits above the tab bar.
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BrandApp(routerConfig: router));
    await tester.pumpAndSettle();
    if (!openAccount) return;
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

  for (final signedIn in [true, false]) {
    testWidgets('without a support link from the panel, «Поддержка» opens the '
        'bot\'s support (signed in: $signedIn)', (tester) async {
      final launcher = useFakeUrlLauncher();
      await pumpAccount(tester, signedIn: signedIn);

      await tester.ensureVisible(find.text('Поддержка'));
      await tester.tap(find.text('Поддержка'));
      await settle(tester);

      expect(launcher.opened, ['https://t.me/launchbotsupport']);
    });
  }

  testWidgets('an account with only Telegram says it signs in with Telegram', (
    tester,
  ) async {
    await pumpAccount(tester, telegramOnly: true);

    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Вход через Telegram'), findsOneWidget);
    expect(find.text('Привязать Telegram'), findsNothing);
  });

  for (final (linkSubscription, ended) in [
    (null, true),
    ('https://sub.launch.tel/from-bot', false),
  ]) {
    testWidgets('an ended account shows «Подписка закончилась» only without '
        'a subscription on the device (one from a link: '
        '${linkSubscription != null})', (tester) async {
      await pumpAccount(
        tester,
        accountActive: false,
        linkSubscription: linkSubscription,
      );

      expect(
        find.text('Подписка закончилась'),
        ended ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('an account whose trial waits on Telegram says so instead of '
      'ended', (tester) async {
    api.trialOffer('telegram_required');
    await pumpAccount(
      tester,
      accountActive: false,
      distribution: AppDistribution.apk,
    );

    expect(find.text('Пробный период — через Telegram'), findsOneWidget);
    expect(
      find.text(
        'Для этой почты нужен Telegram. Привяжите его, и пробный период '
        'начнётся сразу.',
      ),
      findsOneWidget,
    );
    expect(find.text('Подписка закончилась'), findsNothing);
    expect(find.text('Привязать Telegram'), findsOneWidget);
    expect(find.text('Купить подписку'), findsOneWidget);
    expect(find.text('Продлить подписку'), findsNothing);
  });

  testWidgets('without the account details, the trial still offers to link '
      'Telegram', (tester) async {
    api.trialOffer('telegram_required');
    await pumpAccount(tester, accountActive: false, detailsLoad: false);

    expect(find.text('Пробный период — через Telegram'), findsOneWidget);
    expect(find.text('Привязать Telegram'), findsOneWidget);
  });

  testWidgets('the APK build renews on the site', (tester) async {
    await pumpAccount(tester, distribution: AppDistribution.apk);

    expect(find.text('Продлить подписку'), findsOneWidget);
  });

  testWidgets('another device is removed from its sheet', (tester) async {
    await pumpAccount(tester);
    expect(find.text('Устройства · 2 из 5'), findsOneWidget);
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
    expect(find.text('Устройства · 1 из 5'), findsOneWidget);
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
      account.telegram.browser.handleReturn(
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

    testWidgets('a link the system closed the App during completes after the '
        'restart on «Аккаунт»', (tester) async {
      await pumpAccount(tester);
      api.linkStartWith('https://app.test/api/auth/telegram/start?ticket=t1');
      await tester.ensureVisible(find.text('Привязать Telegram'));
      await tester.tap(find.text('Привязать Telegram'));
      await settle(tester);
      expect(browser.opened, hasLength(1));
      api.refreshWith(access: 'a2', refresh: 'r2');
      api.exchangeWith(access: 'a3', refresh: 'r3', addedDays: 30);
      // In the test's zone: the attempt completes in the zone it was
      // restored in.
      account = accountServiceFor(
        api,
        removeSubscription: (url) async => removed.add(url),
        browser: browser,
      );
      await account.restore();
      await pumpAccount(tester, openAccount: false);
      expect(find.text('home-body'), findsOneWidget);
      api.me(email: 'ivan@proton.me', telegramLinked: true);

      links.add(Uri.parse('launchvpn://auth?code=c1&mode=link'));
      await settle(tester);

      expect(find.text('Telegram привязан, 30 дней добавлены'), findsOneWidget);
      expect(find.text('Привязать Telegram'), findsNothing);
    });

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

    testWidgets('with the session already gone, «Вход» asks to sign in again '
        'to delete', (tester) async {
      await pumpAccount(tester);
      api.rejectAccess('a1');
      api.refuseRefresh();

      await deleteAndConfirm(tester);

      expect(find.text('Войдите снова, чтобы удалить аккаунт'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Войти'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(removed, ['https://sub.launch.tel/abc']);
    });

    testWidgets('with the session gone and a subscription from a link kept, '
        '«Вход» opens over the tabs', (tester) async {
      await pumpAccount(
        tester,
        linkSubscription: 'https://sub.launch.tel/from-bot',
      );
      api.rejectAccess('a1');
      api.refuseRefresh();

      await deleteAndConfirm(tester);

      expect(find.text('Войдите снова, чтобы удалить аккаунт'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Войти'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Войти'), findsOneWidget);
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
