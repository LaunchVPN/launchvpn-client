import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/app.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/router.dart';
import 'package:onexray/brand/settings/controller.dart';
import 'package:onexray/brand/settings/page.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/keep_vpn_on.dart';
import 'package:onexray/service/connect/preset.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/crash_reports/service.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/servers/subscription/renewal_reminders.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/share/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_crash_reporter.dart';
import '../../support/fake_notifications.dart';

final class _Store extends InMemorySharedPreferencesAsync {
  _Store() : super.empty();

  bool failReads = false;

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async {
    if (failReads) throw StateError('unreadable');
    return super.getBool(key, options);
  }
}

ConnectionRuntime _runtime({
  ConnectionPlatform platform = ConnectionPlatform.android,
}) => ConnectionRuntime.create(
  configuration: ConnectionConfiguration(),
  compiled: CompiledConnection(
    xrayJson: '{}',
    entries: const [],
    finalExit: null,
    nodeTags: const {},
    profile: ResolvedProfile(
      id: 7,
      sourceId: 1,
      name: 'AUTO | Fastest',
      config: const {},
    ),
  ),
  platform: platform,
  request: StartVpnRequest(null, null, '18003', '{}'),
  startedAt: DateTime(2026),
);

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late HomeController controller;
  late FakeNotifications notifications;
  late RenewalReminders reminders;
  late FakeCrashReporter crashReporter;
  late CrashReports crashReports;
  late Completer<HostConnection> start;
  var status = VpnStatus.disconnected;
  var starts = 0;
  ConnectionRuntime? runtime;

  // PreferencesKey keeps the first platform it sees, so tests share one store.
  final store = _Store();
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = store);

  setUp(() async {
    store.failReads = false;
    await SharedPreferencesAsync().clear();
    // As on every launch after the first, whose toast would cover the tabs.
    await PreferencesKey().saveCrashReportsNoticeShown();
    start = Completer();
    status = VpnStatus.disconnected;
    starts = 0;
    runtime = null;
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => pumpEventQueue(times: 20));
    await tester.pumpAndSettle();
  }

  // A relaunch: main reads the saved language before the first frame.
  Future<void> pumpRouter(WidgetTester tester) async {
    final bus = AppEventBus();
    await tester.runAsync(bus.asyncInitTheme);
    final links = StreamController<Uri>.broadcast(sync: true);
    final share = ShareService.forTesting(
      appLinks: links.stream,
      receiveWidgetUri: (_) => false,
    );
    addTearDown(() async {
      share.dispose();
      await links.close();
    });
    final GoRouter router = createBrandRouter(
      controller: controller,
      settings: BrandSettingsPage(
        controller: controller,
        reminders: reminders,
        crashReports: crashReports,
      ),
      shareService: share,
      watchSubscription: () => Stream.value(true),
      initializeServices: (_) => share.init(),
      openLink: (_, _) async {},
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(BrandApp(routerConfig: router, eventBus: bus));
    await settle(tester);
  }

  HomeController homeController({
    ConnectionPlatform platform = ConnectionPlatform.ios,
    List<AndroidAppInfo> apps = const [],
  }) {
    final home = HomeController(
      database: db,
      coordinator: coordinator,
      pingLocations: (_, {isCancelled}) async {},
      dismissAnnounce: db.subscriptionDao.dismissAnnounce,
      platform: platform,
      installedApps: () async => apps,
    );
    addTearDown(home.close);
    return home;
  }

  /// On a Russian phone unless [system] says otherwise.
  Future<void> pumpApp(
    WidgetTester tester, {
    Locale system = const Locale('ru'),
    ConnectionPlatform platform = ConnectionPlatform.ios,
    List<AndroidAppInfo> apps = const [],
  }) async {
    tester.platformDispatcher
      ..localeTestValue = system
      ..localesTestValue = [system];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    notifications = FakeNotifications();
    reminders = RenewalReminders(database: db, notifications: notifications);
    // As main leaves it on a first launch.
    crashReporter = FakeCrashReporter()..sending = true;
    crashReports = CrashReports(reporter: crashReporter);
    final statusEvents = StreamController<VpnStatus>.broadcast(sync: true);
    addTearDown(statusEvents.close);
    await tester.runAsync(() async {
      coordinator = ConnectionCoordinator(
        database: db,
        statusEvents: statusEvents.stream,
        observeStatus: () async {},
        disposeStatus: () {},
        readRuntime: () async => runtime,
        inspect: (current, {observedStatus}) async =>
            HostConnection(observedStatus ?? status, runtime: current),
        prepare: (_, _) async => _runtime(),
        start: (_) {
          starts++;
          return start.future;
        },
        stop: () async => const HostConnection(VpnStatus.disconnected),
      );
      await coordinator.initialize(registerReferences: false);
      await db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'LaunchVPN',
          url: 'https://sub.launch.tel/a',
          timestamp: DateTime(2026),
          mode: Value(SubscriptionMode.providerManaged.name),
          userInfoUpdatedAt: Value(DateTime(2026)),
        ),
      );
    });
    addTearDown(coordinator.dispose);
    controller = homeController(platform: platform, apps: apps);
    await pumpRouter(tester);
  }

  Future<void> openTab(WidgetTester tester, int index) async {
    await tester.tap(find.byType(NavigationDestination).at(index));
    await settle(tester);
  }

  testWidgets('the mode row follows a choice made on Home', (tester) async {
    await pumpApp(tester);

    await openTab(tester, 2);
    expect(find.text('Режим'), findsOneWidget);
    expect(find.text('Умный'), findsOneWidget);

    await openTab(tester, 0);
    await tester.tap(find.text('Всё через VPN'));
    await settle(tester);

    await openTab(tester, 2);
    expect(find.text('Всё через VPN'), findsOneWidget);
    expect(find.text('Умный'), findsNothing);
  });

  Tristate isToggled(WidgetTester tester, String title) => tester
      .getSemantics(find.bySemanticsLabel(RegExp('^$title')))
      .flagsCollection
      .isToggled;

  group('connect at launch', () {
    const title = 'Подключать при запуске';

    Tristate toggled(WidgetTester tester) => isToggled(tester, title);

    testWidgets('is off until the user turns it on', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 2);

      expect(toggled(tester), Tristate.isFalse);
    });

    testWidgets('a tap anywhere on the row turns it on and off', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 2);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isTrue);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SettingsSwitchRow, title),
          matching: find.byType(ShadSwitch),
        ),
      );
      await settle(tester);
      expect(toggled(tester), Tristate.isFalse);
    });

    testWidgets('an unreadable value reads as off and can still be changed', (
      tester,
    ) async {
      store.failReads = true;
      await pumpApp(tester);
      await openTab(tester, 2);
      expect(toggled(tester), Tristate.isFalse);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isTrue);
    });

    test('a second tap during a save is ignored', () async {
      final settings = SettingsController(
        reminders: RenewalReminders(notifications: FakeNotifications()),
      );
      addTearDown(settings.close);
      await settings.initialize();

      final first = settings.setConnectOnLaunch(true);
      await settings.setConnectOnLaunch(false);
      await first;

      expect(settings.state.connectOnLaunch, isTrue);
      expect(await AppStartupService().readConnectOnAppLaunch(), isTrue);
    });

    testWidgets('is remembered for the next launch', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 2);
      await tester.tap(find.text(title));
      await settle(tester);

      await tester.pumpWidget(const SizedBox());
      await pumpRouter(tester);
      await openTab(tester, 2);

      expect(toggled(tester), Tristate.isTrue);
    });
  });

  group('renewal reminders', () {
    const title = 'Напоминать о продлении';

    Tristate toggled(WidgetTester tester) => isToggled(tester, title);

    testWidgets('are on by default, under App', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 2);

      expect(find.text('ПРИЛОЖЕНИЕ'), findsOneWidget);
      expect(find.text('За 3 дня и за 1 день'), findsOneWidget);
      expect(toggled(tester), Tristate.isTrue);
    });

    testWidgets('a tap turns them off and on, and it is saved', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 2);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isFalse);
      expect(await tester.runAsync(() => reminders.active), isFalse);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isTrue);
      expect(await tester.runAsync(() => reminders.active), isTrue);
    });

    testWidgets('without notifications the switch is off until the person '
        'allows them in the system settings', (tester) async {
      await pumpApp(tester);
      notifications.allowed = false;
      await openTab(tester, 2);
      expect(toggled(tester), Tristate.isFalse);

      notifications.prompt = Completer();
      await tester.tap(find.text(title));
      await settle(tester);
      // Off while the system prompt is open, since nothing is allowed yet.
      expect(toggled(tester), Tristate.isFalse);

      notifications.prompt!.complete();
      await settle(tester);
      expect(notifications.settingsOpened, 1);
      expect(toggled(tester), Tristate.isFalse);

      notifications.allowed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(toggled(tester), Tristate.isTrue);
    });
  });

  group('crash reports', () {
    const title = 'Отчёты о сбоях';

    Tristate toggled(WidgetTester tester) => isToggled(tester, title);

    testWidgets('are on by default, under App, and say what they leave out', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 2);
      await tester.scrollUntilVisible(find.text(title), 100);

      expect(find.text('Без ссылок, адресов и email'), findsOneWidget);
      expect(toggled(tester), Tristate.isTrue);
    });

    testWidgets('off stops sending and is remembered; on sends again', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 2);
      await tester.scrollUntilVisible(find.text(title), 100);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isFalse);
      expect(crashReporter.sending, isFalse);

      // The next launch, as main starts it.
      crashReporter = FakeCrashReporter();
      crashReports = CrashReports(reporter: crashReporter);
      await tester.runAsync(crashReports.start);
      expect(crashReporter.sending, isFalse);

      await tester.pumpWidget(const SizedBox());
      await pumpRouter(tester);
      await openTab(tester, 2);
      await tester.scrollUntilVisible(find.text(title), 100);
      expect(toggled(tester), Tristate.isFalse);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isTrue);
      expect(crashReporter.sending, isTrue);
    });
  });

  group('the preset screen', () {
    Future<void> openPresets(WidgetTester tester) async {
      await openTab(tester, 2);
      await tester.tap(find.text('Режим'));
      await settle(tester);
    }

    Tristate selected(WidgetTester tester, String label) => tester
        .getSemantics(find.bySemanticsLabel(RegExp('^$label')))
        .flagsCollection
        .isSelected;

    testWidgets('marks the current mode and offers both presets on iOS', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPresets(tester);

      expect(
        find.text('Сайты, которым VPN не нужен, открываются напрямую'),
        findsOneWidget,
      );
      expect(find.text('Весь трафик идёт через сервер'), findsOneWidget);
      expect(
        find.text('Режим можно сменить и на главном экране.'),
        findsOneWidget,
      );
      expect(find.text('Приложения'), findsNothing);
      expect(selected(tester, 'Умный'), Tristate.isTrue);
      expect(selected(tester, 'Всё через VPN'), Tristate.isFalse);
    });

    testWidgets('a choice returns to settings, saves and reaches Home', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPresets(tester);

      await tester.tap(find.text('Всё через VPN'));
      await settle(tester);

      expect(find.text('Весь трафик идёт через сервер'), findsNothing);
      expect(find.text('Всё через VPN'), findsOneWidget);
      await tester.runAsync(() async {
        expect(
          (await coordinator.configuration).connection.trafficMode,
          TrafficMode.allVpn,
        );
      });

      await openTab(tester, 0);
      expect(selected(tester, 'Всё через VPN'), Tristate.isTrue);
    });

    testWidgets('the current mode closes the screen without a change', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPresets(tester);

      await tester.tap(find.text('Умный'));
      await settle(tester);

      expect(find.text('Весь трафик идёт через сервер'), findsNothing);
      expect(find.text('Умный'), findsOneWidget);
    });

    testWidgets('while connected a choice reconnects and Home says so', (
      tester,
    ) async {
      await pumpApp(tester);
      runtime = _runtime();
      status = VpnStatus.connected;
      await tester.runAsync(coordinator.refresh);
      await openPresets(tester);

      await tester.tap(find.text('Всё через VPN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => pumpEventQueue(times: 20));
      await tester.tap(find.byType(NavigationDestination).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Переподключение…'), findsOneWidget);

      start.complete(HostConnection(VpnStatus.connected, runtime: runtime));
      await tester.runAsync(() => pumpEventQueue(times: 20));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('nothing can be chosen while a command runs', (tester) async {
      await pumpApp(tester);
      final applying = Completer<void>();
      final choice = controller.selectPreset(
        ConnectionPreset.allVpn,
        (_) => applying.future,
      );
      await tester.pump();
      await openPresets(tester);

      await tester.tap(find.text('Умный'));
      await tester.pump();
      expect(find.text('Весь трафик идёт через сервер'), findsOneWidget);

      applying.complete();
      await choice;
    });

    testWidgets('fits with the largest system font', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester);
      await openPresets(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('apps through VPN', () {
    const title = 'Приложения через VPN';
    final apps = [
      AndroidAppInfo(
        name: 'YouTube',
        packageName: 'com.google.android.youtube',
      ),
      AndroidAppInfo(name: 'Telegram', packageName: 'org.telegram.messenger'),
      AndroidAppInfo(name: 'Госуслуги', packageName: 'ru.rostel'),
      AndroidAppInfo(name: 'LaunchVPN', packageName: 'com.launchvpn.app'),
    ];

    Future<void> pumpAndroid(WidgetTester tester) async {
      await pumpApp(tester, platform: ConnectionPlatform.android, apps: apps);
      await openTab(tester, 2);
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await settle(tester);
    }

    Future<ConnectionConfiguration> stored(WidgetTester tester) async =>
        (await tester.runAsync(() => coordinator.configuration))!;

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('is not on iOS', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 2);

      expect(find.text(title), findsNothing);
    });

    testWidgets('Apps with nothing chosen opens the list, which then '
        'counts in settings', (tester) async {
      await pumpAndroid(tester);
      expect(find.text('Остальные идут напрямую'), findsOneWidget);
      await tester.tap(find.text('Режим'));
      await settle(tester);

      await tester.tap(find.text('Приложения'));
      await settle(tester);
      await tester.tap(find.text('Telegram'));
      await tester.pump();
      await leave(tester);

      expect(find.text('Приложения'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      final configuration = await stored(tester);
      expect(
        ConnectionPreset.of(
          configuration,
          platform: ConnectionPlatform.android,
        ),
        ConnectionPreset.apps,
      );
      expect(configuration.vpnApps, ['org.telegram.messenger']);
    });

    testWidgets('lists the chosen apps first and finds apps by name', (
      tester,
    ) async {
      await pumpAndroid(tester);
      await tester.runAsync(
        () => coordinator.applyChange(
          (current) => current.withVpnApps(['ru.rostel']),
          restart: false,
        ),
      );
      await settle(tester);
      await tester.tap(find.text(title));
      await settle(tester);

      expect(find.text('ЧЕРЕЗ VPN · 1'), findsOneWidget);
      expect(find.text('LaunchVPN'), findsNothing);
      expect(top(tester, 'Госуслуги'), lessThan(top(tester, 'ОСТАЛЬНЫЕ')));
      expect(top(tester, 'Telegram'), lessThan(top(tester, 'YouTube')));

      await tester.enterText(find.byType(TextField), 'tele');
      await tester.pump();
      expect(find.text('Telegram'), findsOneWidget);
      expect(find.text('YouTube'), findsNothing);
      expect(find.text('Госуслуги'), findsNothing);

      await tester.enterText(find.byType(TextField), 'нет такого');
      await tester.pump();
      expect(find.text('Ничего не найдено'), findsOneWidget);
    });

    testWidgets('builds only the rows on screen', (tester) async {
      await pumpApp(
        tester,
        platform: ConnectionPlatform.android,
        apps: [
          for (var i = 100; i < 300; i++)
            AndroidAppInfo(name: 'App $i', packageName: 'app.n$i'),
        ],
      );
      await openTab(tester, 2);
      await tester.tap(find.text(title));
      await settle(tester);

      expect(find.text('App 100'), findsOneWidget);
      expect(find.text('App 299'), findsNothing);
    });

    testWidgets('a refused list keeps the choice', (tester) async {
      await pumpApp(tester, platform: ConnectionPlatform.android);
      await tester.runAsync(
        () => coordinator.applyChange(
          (current) =>
              ConnectionPreset.apps.applyTo(current.withVpnApps(['ru.rostel'])),
          restart: false,
        ),
      );
      await openTab(tester, 2);
      await tester.tap(find.text(title));
      await settle(tester);

      expect(find.text('Не удалось получить список приложений'), findsOne);
      await leave(tester);

      final configuration = await stored(tester);
      expect(configuration.vpnApps, ['ru.rostel']);
      expect(
        ConnectionPreset.of(
          configuration,
          platform: ConnectionPlatform.android,
        ),
        ConnectionPreset.apps,
      );
    });

    testWidgets('a list changed under another mode keeps the mode', (
      tester,
    ) async {
      await pumpAndroid(tester);
      await tester.tap(find.text(title));
      await settle(tester);

      await tester.tap(find.text('YouTube'));
      await tester.pump();
      await leave(tester);

      expect(find.text('Умный'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect((await stored(tester)).vpnApps, ['com.google.android.youtube']);
    });
  });

  group('keep VPN on', () {
    const title = 'Не отключать VPN';

    Tristate toggled(WidgetTester tester) => isToggled(tester, title);

    Future<bool> stored(WidgetTester tester) async =>
        (await tester.runAsync(() => coordinator.configuration))!.keepVpnOn;

    testWidgets('is off by default on iPhone', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 2);

      expect(
        find.text('Включается сам после перезагрузки и смены сети'),
        findsOneWidget,
      );
      expect(toggled(tester), Tristate.isFalse);
    });

    testWidgets('is not on Android', (tester) async {
      await pumpApp(tester, platform: ConnectionPlatform.android);
      await openTab(tester, 2);

      expect(find.text(title), findsNothing);
    });

    testWidgets('a tap turns it on and off, and it is remembered for the next '
        'launch', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 2);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isTrue);
      expect(await stored(tester), isTrue);

      await tester.pumpWidget(const SizedBox());
      controller = homeController();
      await pumpRouter(tester);
      await openTab(tester, 2);
      expect(toggled(tester), Tristate.isTrue);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isFalse);
      expect(await stored(tester), isFalse);
    });

    testWidgets('is disabled while a command runs', (tester) async {
      await pumpApp(tester);
      final applying = Completer<void>();
      final choice = controller.selectPreset(
        ConnectionPreset.allVpn,
        (_) => applying.future,
      );
      await openTab(tester, 2);

      Tristate enabled() => tester
          .getSemantics(find.bySemanticsLabel(RegExp('^$title')))
          .flagsCollection
          .isEnabled;
      expect(enabled(), Tristate.isFalse);
      await tester.tap(find.text(title));
      await tester.pump();
      expect(toggled(tester), Tristate.isFalse);

      applying.complete();
      await choice;
      await settle(tester);
      expect(enabled(), Tristate.isTrue);
    });

    testWidgets('while connected it waits for the next connection', (
      tester,
    ) async {
      await pumpApp(tester);
      runtime = _runtime(platform: ConnectionPlatform.ios);
      status = VpnStatus.connected;
      await tester.runAsync(coordinator.refresh);
      await openTab(tester, 2);

      await tester.tap(find.text(title));
      await settle(tester);

      expect(toggled(tester), Tristate.isTrue);
      expect(await stored(tester), isTrue);
      // The save is over without a reconnect, so the row works again.
      expect(controller.state.canChangeConnection, isTrue);
      expect(starts, 0);
    });
  });

  group('language', () {
    test('the last tap wins over a save still running', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      // Closing it would dispose the App's services.
      final bus = AppEventBus();
      final settings = SettingsController(
        reminders: RenewalReminders(
          database: db,
          notifications: FakeNotifications(),
        ),
      );
      addTearDown(settings.close);

      final english = settings.setLanguage(LanguageCode.en);
      await settings.setLanguage(LanguageCode.system);
      await english;

      expect(bus.state.languageCode, LanguageCode.system);
      expect(await PreferencesKey().readLanguageCode(), 'system');
    });

    testWidgets('an English phone gets English on Home and in Settings', (
      tester,
    ) async {
      await pumpApp(tester, system: const Locale('en', 'US'));

      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Smart'), findsOneWidget);

      await openTab(tester, 2);
      expect(find.text('CONNECTION'), findsOneWidget);
      expect(find.text('Connect at launch'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Same as system'), findsOneWidget);
    });

    Tristate selected(WidgetTester tester, String label) => tester
        .getSemantics(find.bySemanticsLabel(RegExp('^$label')))
        .flagsCollection
        .isSelected;

    testWidgets('English applies at once and stays for the next launch', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.runAsync(() async {
        final row = (await db.subscriptionDao.allRows).single;
        final expires = DateTime.now().add(const Duration(days: 30));
        await db.subscriptionDao.updateRow(
          row.copyWith(
            expireTimestamp: Value(expires.millisecondsSinceEpoch ~/ 1000),
          ),
        );
      });
      await openTab(tester, 2);
      expect(find.text('Как в системе'), findsOneWidget);

      await tester.tap(find.text('Язык'));
      await settle(tester);
      expect(find.text('Сейчас русский'), findsOneWidget);
      expect(selected(tester, 'Как в системе'), Tristate.isTrue);
      expect(selected(tester, 'Русский'), Tristate.isFalse);
      expect(selected(tester, 'English'), Tristate.isFalse);

      await tester.tap(find.text('English'));
      await settle(tester);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Currently Russian'), findsOneWidget);
      expect(selected(tester, 'English'), Tristate.isTrue);
      // The reminders already set are rewritten in English.
      expect(notifications.shown.map((r) => r.$2), [
        'Your subscription ends in 3 days',
        'Your subscription ends tomorrow',
      ]);

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await settle(tester);
      expect(find.text('Connect at launch'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpRouter(tester);
      expect(find.text('Not connected'), findsOneWidget);
    });
  });
}
