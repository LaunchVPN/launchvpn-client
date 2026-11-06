// Test code that screenshots_test.dart runs, outside `test/` by name only.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/brand/account/page.dart';
import 'package:onexray/brand/app.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/home/page.dart';
import 'package:onexray/brand/router.dart';
import 'package:onexray/brand/settings/page.dart';
import 'package:onexray/brand/text_field.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/renewal_reminders.dart';
import 'package:onexray/service/shared/share/service.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../test/support/fake_account_api.dart';
import '../../test/support/fake_notifications.dart';
import 'store.dart';

/// What each screenshot shows, in the stores' order.
enum Shot {
  connected(ru: 'VPN в одно касание', en: 'One tap to connect'),
  locations(
    ru: 'Быстрый сервер выбирается сам',
    en: 'The fastest server, picked for you',
  ),
  settings(
    ru: 'Умный режим и автоподключение',
    en: 'Smart mode and auto-connect',
  ),
  account(ru: 'Подписка и устройства', en: 'Your plan and devices'),
  login(
    ru: '3 дня бесплатно, карта не нужна',
    en: '3 days free, no card needed',
  );

  const Shot({required this.ru, required this.en});
  final String ru;
  final String en;

  String caption(StoreLanguage language) => switch (language) {
    StoreLanguage.ru => ru,
    StoreLanguage.en => en,
  };
}

/// Never shown: the screens name no link.
const _subscriptionUrl = 'https://sub.launch.tel/store';

/// The panel's groups as a subscription delivers them, with their last ping.
const _groups = {
  StoreLanguage.ru: [
    ('🇪🇺 AUTO | Самые быстрые', 48),
    ('🇩🇪 Германия', 52),
    ('🇳🇱 Нидерланды', 61),
    ('🇫🇮 Финляндия', 39),
    ('🇸🇪 Швеция', 74),
    ('🇵🇱 Польша', 66),
  ],
  StoreLanguage.en: [
    ('🇪🇺 AUTO | Fastest', 48),
    ('🇩🇪 Germany', 52),
    ('🇳🇱 Netherlands', 61),
    ('🇫🇮 Finland', 39),
    ('🇸🇪 Sweden', 74),
    ('🇵🇱 Poland', 66),
  ],
};

/// The App on test data, signed in with a subscription unless the shot is
/// [Shot.login].
class Scene {
  Scene._(this.app, this._router, this._shot, this._home);

  final Widget app;
  final GoRouter _router;
  final Shot _shot;
  final HomeController _home;

  static Future<Scene> start(
    WidgetTester tester,
    Shot shot,
    StoreDevice device,
    StoreLanguage language,
  ) async {
    tester.platformDispatcher
      ..localeTestValue = language.locale
      ..localesTestValue = [language.locale];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
    await tester.runAsync(PreferencesKey().saveCrashReportsNoticeShown);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final groups = _groups[language]!;
    // Signed in and connected, except on «Вход».
    final signedIn = shot != Shot.login;
    final statusEvents = StreamController<VpnStatus>.broadcast(sync: true);
    addTearDown(statusEvents.close);
    final runtime = ConnectionRuntime.create(
      configuration: ConnectionConfiguration(),
      compiled: CompiledConnection(
        xrayJson: '{}',
        entries: const [],
        finalExit: null,
        nodeTags: const {},
        profile: ResolvedProfile(
          id: 1,
          sourceId: 1,
          name: groups.first.$1,
          config: const {},
        ),
      ),
      platform: device.platform.connection,
      request: StartVpnRequest(null, null, '18003', '{}'),
      startedAt: DateTime.now().subtract(
        const Duration(minutes: 24, seconds: 17),
      ),
    );
    late ConnectionCoordinator coordinator;
    await tester.runAsync(() async {
      await _seed(db, groups);
      coordinator = ConnectionCoordinator(
        database: db,
        statusEvents: statusEvents.stream,
        observeStatus: () async {},
        disposeStatus: () {},
        readRuntime: () async => signedIn ? runtime : null,
        inspect: (current, {observedStatus}) async => HostConnection(
          signedIn ? VpnStatus.connected : VpnStatus.disconnected,
          runtime: current,
        ),
        prepare: (_, _) async => runtime,
        start: (_) async =>
            HostConnection(VpnStatus.connected, runtime: runtime),
        stop: () async => const HostConnection(VpnStatus.disconnected),
      );
      await coordinator.initialize(registerReferences: false);
    });
    addTearDown(coordinator.dispose);

    final api = FakeAccountApi()
      ..loginWith(access: 'a1', refresh: 'r1')
      ..subscription(_subscriptionUrl, maxDevices: 5)
      ..me(email: 'anna@example.com', telegramLinked: true)
      ..devices([
        {
          'hwid': 'device-hwid',
          'deviceModel': device.platform.model,
          'platform': device.platform.system,
        },
        {
          'hwid': 'laptop',
          'deviceModel': 'MacBook Air',
          'platform': 'macOS',
          'osVersion': '26',
        },
      ], max: 5);
    final account = accountServiceFor(api);
    if (signedIn) {
      await tester.runAsync(
        () => account.email.login(email: 'anna@example.com', password: 'pw'),
      );
    }

    Future<SubscriptionRefreshResult> refresh(SubscriptionData _) async =>
        const SubscriptionRefreshResult(
          status: SubscriptionUpdateResult.success,
        );
    final deviceLimit = ValueNotifier(false);
    final home = HomeController(
      database: db,
      coordinator: coordinator,
      pingLocations: (_, {isCancelled}) async {},
      dismissAnnounce: db.subscriptionDao.dismissAnnounce,
      refreshSubscription: refresh,
      platform: device.platform.connection,
      installedApps: () async => const [],
      deviceLimit: deviceLimit,
      widgetContext: ({location, preset, expiresAt}) async {},
    );
    final accountController = AccountController(
      account: account,
      subscriptions: SubscriptionLinkService(database: db),
      refreshSubscription: refresh,
      deviceLimit: deviceLimit,
    );
    addTearDown(accountController.close);
    final share = ShareService.forTesting(
      appLinks: const Stream.empty(),
      receiveWidgetUri: (_) => false,
    );
    addTearDown(share.dispose);
    final router = createBrandRouter(
      controller: home,
      home: HomePage(controller: home, account: accountController),
      accountTab: AccountPage(controller: accountController, account: account),
      settings: BrandSettingsPage(
        controller: home,
        reminders: RenewalReminders(
          database: db,
          notifications: FakeNotifications(),
        ),
      ),
      account: account,
      shareService: share,
      watchSubscription: () => Stream.value(signedIn),
      initializeServices: (_) async => share.init(),
    );
    addTearDown(router.dispose);
    return Scene._(BrandApp(routerConfig: router), router, shot, home);
  }

  static Future<void> _seed(AppDatabase db, List<(String, int)> groups) async {
    await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'LaunchVPN',
        url: _subscriptionUrl,
        timestamp: DateTime(2026),
        mode: Value(SubscriptionMode.providerManaged.name),
        expireTimestamp: Value(
          DateTime.now()
                  .add(const Duration(days: 27, hours: 2))
                  .millisecondsSinceEpoch ~/
              1000,
        ),
        userInfoUpdatedAt: Value(DateTime(2026)),
      ),
    );
    for (final (name, delay) in groups) {
      await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: name,
          type: CoreConfigType.Remnawave.name,
          tags: '',
          delay: delay,
          subId: 1,
          data: Value(
            base64Encode(
              utf8.encode(
                jsonEncode({
                  'outbounds': [
                    {'tag': 'proxy', 'protocol': 'vless'},
                  ],
                }),
              ),
            ),
          ),
        ),
      );
    }
  }

  /// Lets the App start, then opens the shot's screen.
  Future<void> settle(WidgetTester tester) async {
    Future<void> idle() async {
      await tester.runAsync(() => pumpEventQueue(times: 50));
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => pumpEventQueue(times: 50));
      await tester.pump(const Duration(seconds: 2));
    }

    await idle();
    switch (_shot) {
      case Shot.connected:
        break;
      case Shot.locations:
        await tester.tap(find.byKey(const ValueKey('home-location')));
      case Shot.account:
        _router.go(BrandRoutes.account);
      case Shot.settings:
        _router.go(BrandRoutes.settings);
        await idle();
        final page = tester.element(find.byType(BrandSettingsPage));
        await tester.tap(
          find.text(AppLocalizations.of(page)!.settingsConnectOnLaunch),
        );
      case Shot.login:
        await _fillLogin(tester);
    }
    await idle();
  }

  /// Fills «Вход», so its button shows ready.
  static Future<void> _fillLogin(WidgetTester tester) async {
    final fields = find.descendant(
      of: find.byType(BrandTextField),
      matching: find.byType(EditableText),
    );
    await tester.enterText(fields.first, 'anna@example.com');
    await tester.enterText(fields.last, 'launch-2026');
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Ends the App and Home's day timer before the test checks for timers.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(_home.close);
  }
}
