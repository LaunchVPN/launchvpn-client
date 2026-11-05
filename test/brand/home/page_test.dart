import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:country_flags/country_flags.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/home/page.dart';
import 'package:onexray/brand/home/toggle.dart';
import 'package:onexray/brand/home/update_banner.dart';
import 'package:onexray/brand/locations/page.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/distribution.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/preset.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../support/fake_account_api.dart';
import '../../support/fake_url_launcher.dart';

const _largeScale = 3.0;

Tristate isSelected(WidgetTester tester, String label) => tester
    .getSemantics(find.bySemanticsLabel(label))
    .flagsCollection
    .isSelected;

ConnectionRuntime _runtime(DateTime startedAt) => ConnectionRuntime.create(
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
  platform: ConnectionPlatform.android,
  request: StartVpnRequest(null, null, '18003', '{}'),
  startedAt: startedAt,
);

void main() {
  late AppEventBus bus;
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late HomeController controller;
  late StreamController<VpnStatus> statusEvents;
  late Completer<HostConnection> start;
  var status = VpnStatus.disconnected;
  ConnectionRuntime? runtime;
  late Future<void> Function() prepareFailure;
  var prepares = 0;
  var sweeps = 0;
  late Future<SubscriptionRefreshResult> Function(SubscriptionData) refresh;
  late ValueNotifier<bool> deviceLimit;

  Future<void> pumpHome(
    WidgetTester tester, {
    double scale = 1,
    AppDistribution distribution = AppDistribution.current,
    Locale locale = const Locale('ru'),
    ConnectionPlatform platform = ConnectionPlatform.ios,
    List<AndroidAppInfo> apps = const [],
    AccountService? account,
  }) async {
    bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    statusEvents = StreamController<VpnStatus>.broadcast(sync: true);
    addTearDown(statusEvents.close);
    start = Completer();
    await tester.runAsync(() async {
      coordinator = ConnectionCoordinator(
        database: db,
        statusEvents: statusEvents.stream,
        observeStatus: () async {},
        disposeStatus: () {},
        readRuntime: () async => runtime,
        inspect: (current, {observedStatus}) async =>
            HostConnection(observedStatus ?? status, runtime: current),
        prepare: (_, _) async {
          prepares++;
          await prepareFailure();
          return _runtime(DateTime(2026));
        },
        start: (_) => start.future,
        stop: () async => const HostConnection(VpnStatus.disconnected),
      );
      await coordinator.initialize(registerReferences: false);
    });
    addTearDown(coordinator.dispose);
    // Ends a start left waiting before the coordinator closes, so the command
    // finishes instead of failing against a disposed state.
    addTearDown(() async {
      if (start.isCompleted) return;
      start.complete(const HostConnection(VpnStatus.disconnected));
      await tester.runAsync(() => pumpEventQueue(times: 50));
    });
    controller = HomeController(
      database: db,
      coordinator: coordinator,
      pingLocations: (_, {isCancelled}) async => sweeps++,
      dismissAnnounce: db.subscriptionDao.dismissAnnounce,
      refreshSubscription: (row) => refresh(row),
      platform: platform,
      installedApps: () async => apps,
      deviceLimit: deviceLimit = ValueNotifier(false),
    );
    addTearDown(controller.close);
    final accountController = AccountController(
      account: account ?? accountServiceFor(FakeAccountApi()),
      subscriptions: SubscriptionLinkService(database: db),
      refreshSubscription: (row) => refresh(row),
    );
    addTearDown(accountController.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: BrandTheme.material(),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: ShadTheme(
            data: BrandTheme.shad(TextScaler.linear(scale)),
            child: ShadToaster(child: child!),
          ),
        ),
        home: BlocProvider.value(
          value: bus,
          child: HomePage(
            controller: controller,
            account: accountController,
            distribution: distribution,
          ),
        ),
      ),
    );
    await tester.runAsync(() => pumpEventQueue(times: 20));
    await tester.pump();
  }

  Future<void> addSubscription(
    WidgetTester tester, {
    int? expire,
    String? supportUrl,
  }) async {
    await tester.runAsync(() async {
      await db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'LaunchVPN',
          url: 'https://sub.launch.tel/a',
          timestamp: DateTime(2026),
          mode: Value(SubscriptionMode.providerManaged.name),
          expireTimestamp: Value(expire),
          supportUrl: Value(supportUrl),
          userInfoUpdatedAt: Value(DateTime(2026)),
        ),
      );
      await pumpEventQueue(times: 20);
    });
    await tester.pump();
  }

  Future<int> addGroup(
    WidgetTester tester,
    String name, {
    int delay = PingDelayConstants.unknown,
  }) async {
    final id = await tester.runAsync(() async {
      final id = await db.coreConfigDao.insertRow(
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
      await pumpEventQueue(times: 20);
      return id;
    });
    await tester.pump();
    return id!;
  }

  Future<void> openLocations(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home-location')));
    await tester.pumpAndSettle();
    expect(find.byType(LocationsPage), findsOneWidget);
  }

  ConnectToggleState toggleState(WidgetTester tester) =>
      tester.widget<ConnectToggle>(find.byType(ConnectToggle)).state;

  double toggleTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(ConnectToggle)).dy;

  void useScreen(WidgetTester tester, double height) {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  setUp(() {
    status = VpnStatus.disconnected;
    runtime = null;
    prepareFailure = () async {};
    prepares = 0;
    sweeps = 0;
    refresh = (_) async => const SubscriptionRefreshResult(
      status: SubscriptionUpdateResult.success,
    );
  });

  group('locations', () {
    Future<void> pumpGroups(WidgetTester tester) async {
      await pumpHome(tester);
      await addSubscription(tester);
      await addGroup(tester, '🇪🇺 AUTO | Самые быстрые', delay: 860);
      await addGroup(tester, '🇷🇺 AUTO | Обход глушилок');
      await addGroup(tester, '🇩🇪 Германия', delay: 516);
      await addGroup(tester, '🇬🇧 Англия', delay: PingDelayConstants.timeout);
    }

    testWidgets('the card shows the first group, without its panel prefix', (
      tester,
    ) async {
      await pumpGroups(tester);

      expect(find.text('Самые быстрые'), findsOneWidget);
      expect(find.text('860 мс'), findsOneWidget);
      expect(find.textContaining('AUTO'), findsNothing);
    });

    testWidgets('a tap on the card lists automatic groups above the rest', (
      tester,
    ) async {
      await pumpGroups(tester);
      await openLocations(tester);

      final above = tester.getTopLeft(find.text('АВТОМАТИЧЕСКИ')).dy;
      final fastest = tester.getTopLeft(find.text('Самые быстрые').last).dy;
      final others = tester.getTopLeft(find.text('СТРАНЫ И СЕРВИСЫ')).dy;
      final germany = tester.getTopLeft(find.text('Германия')).dy;
      expect(above, lessThan(fastest));
      expect(fastest, lessThan(others));
      expect(others, lessThan(germany));
    });

    testWidgets('countries carry a flag, automatic groups do not', (
      tester,
    ) async {
      await pumpGroups(tester);
      await openLocations(tester);

      expect(find.byType(CountryFlag), findsNWidgets(2));
    });

    testWidgets('shows what the last measurement found', (tester) async {
      await pumpGroups(tester);
      await openLocations(tester);

      expect(find.text('516 мс'), findsOneWidget);
      expect(find.text('Нет ответа'), findsOneWidget);
    });

    testWidgets('opening the list measures it', (tester) async {
      await pumpGroups(tester);
      await openLocations(tester);

      expect(sweeps, 1);
    });

    testWidgets('marks the selected group for sight and for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpGroups(tester);
      await openLocations(tester);

      expect(
        tester
            .getSemantics(find.text('Самые быстрые').last)
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(find.text('Германия')).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      handle.dispose();
    });

    testWidgets('a tap returns home with that location and saves it', (
      tester,
    ) async {
      await pumpGroups(tester);
      await openLocations(tester);

      await tester.tap(find.text('Германия'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => pumpEventQueue(times: 20));
      await tester.pump();

      expect(find.byType(LocationsPage), findsNothing);
      expect(find.text('Германия'), findsOneWidget);
      final stored = await tester.runAsync(() => coordinator.configuration);
      expect(stored!.connection.selection.kind, SelectionKind.server);
    });

    testWidgets('the back button keeps the current location', (tester) async {
      await pumpGroups(tester);
      await openLocations(tester);

      await tester.tap(find.bySemanticsLabel('Назад'));
      await tester.pumpAndSettle();

      expect(find.byType(LocationsPage), findsNothing);
      expect(find.text('Самые быстрые'), findsOneWidget);
      final stored = await tester.runAsync(() => coordinator.configuration);
      expect(stored!.connection.selection.kind, SelectionKind.automatic);
    });

    testWidgets('fits with the largest system font', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpHome(tester, scale: _largeScale);
      await addSubscription(tester);
      await addGroup(tester, '🇫🇮 Финляндия | Способ 2', delay: 674);
      await addGroup(tester, '🇷🇺 AUTO | Обход глушилок Способ 2');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await openLocations(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('announcement', () {
    const notice = 'Сегодня с 02:00 до 03:00 плановые работы';

    Future<void> setAnnounce(WidgetTester tester, String? text) async {
      await tester.runAsync(() async {
        final row = (await db.subscriptionDao.allRows).single;
        await db.subscriptionDao.updateRow(row.copyWith(announce: Value(text)));
        await pumpEventQueue(times: 20);
      });
      await tester.pump();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Закрыть объявление'));
      await tester.runAsync(() => pumpEventQueue(times: 20));
      await tester.pump();
    }

    testWidgets('shows what the panel sent below the presets', (tester) async {
      await pumpHome(tester);
      await addSubscription(tester);
      expect(find.byKey(const ValueKey('home-announcement')), findsNothing);

      await setAnnounce(tester, notice);

      expect(find.text(notice), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(notice)).dy,
        greaterThan(tester.getBottomLeft(find.text('Умный')).dy),
      );
    });

    testWidgets('showing and closing it leaves the toggle in place', (
      tester,
    ) async {
      useScreen(tester, 844);
      await pumpHome(tester);
      await addSubscription(tester);
      final top = toggleTop(tester);

      await setAnnounce(tester, notice);
      expect(toggleTop(tester), top);

      await close(tester);
      expect(toggleTop(tester), top);
    });

    testWidgets('stays closed while the panel has no other text', (
      tester,
    ) async {
      useScreen(tester, 844);
      await pumpHome(tester);
      await addSubscription(tester);
      await setAnnounce(tester, notice);

      await close(tester);
      expect(find.text(notice), findsNothing);

      await setAnnounce(tester, null);
      await setAnnounce(tester, notice);
      expect(find.text(notice), findsNothing);
    });

    testWidgets('a new text shows it again', (tester) async {
      useScreen(tester, 844);
      await pumpHome(tester);
      await addSubscription(tester);
      await setAnnounce(tester, notice);
      await close(tester);

      await setAnnounce(tester, 'Работы закончены');

      expect(find.text('Работы закончены'), findsOneWidget);
    });

    testWidgets('a long text fits with the largest system font', (
      tester,
    ) async {
      useScreen(tester, 844);
      await pumpHome(tester, scale: _largeScale);
      await addSubscription(tester);
      await setAnnounce(tester, List.filled(12, notice).join(' '));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Закрыть объявление'));
      await tester.pumpAndSettle();
      await close(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('home-announcement')), findsNothing);
    });
  });

  group('toggle position', () {
    testWidgets('matches the mockup before anything has loaded', (
      tester,
    ) async {
      useScreen(tester, 706);
      await pumpHome(tester);

      expect(toggleTop(tester), 204);
    });

    testWidgets('the days pill does not move it with a large font', (
      tester,
    ) async {
      useScreen(tester, 844);
      await pumpHome(tester, scale: _largeScale);
      final top = toggleTop(tester);

      final expire = DateTime.now().add(const Duration(days: 46));
      await addSubscription(
        tester,
        expire: expire.millisecondsSinceEpoch ~/ 1000,
      );

      expect(find.byIcon(LucideIcons.calendar).hitTestable(), findsOneWidget);
      expect(toggleTop(tester), top);
    });

    testWidgets('a short screen lifts it to leave room for an announcement', (
      tester,
    ) async {
      useScreen(tester, 600);
      await pumpHome(tester);

      expect(toggleTop(tester), 114);
    });
  });

  group('update banner', () {
    const release =
        'https://github.com/LaunchVPN/launchvpn-client/releases/v1.0.1';

    Future<void> announceUpdate(WidgetTester tester) async {
      bus.updateAppUpdateInfo(
        AppUpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.0.1',
          releaseNotes: '',
          releaseUri: Uri.parse(release),
          updateUri: Uri.parse(release),
          destination: AppUpdateDestination.githubRelease,
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'an APK build offers the newer release, and a tap opens its page',
      (tester) async {
        final launcher = useFakeUrlLauncher();
        await pumpHome(tester, distribution: AppDistribution.apk);

        await announceUpdate(tester);
        expect(find.text('Доступна версия 1.0.1'), findsOneWidget);
        expect(find.text('Текущая версия: 1.0.0'), findsOneWidget);

        await tester.tap(find.text('Доступна версия 1.0.1'));
        await tester.pump();
        expect(launcher.opened, [release]);
      },
    );

    testWidgets('a store build leaves updates to the store', (tester) async {
      await pumpHome(tester, distribution: AppDistribution.store);

      await announceUpdate(tester);

      expect(find.textContaining('Доступна версия'), findsNothing);
    });

    testWidgets('the toggle centers below it as in the mockup', (tester) async {
      useScreen(tester, 706);
      await pumpHome(tester, distribution: AppDistribution.apk);

      await announceUpdate(tester);

      final banner = tester.getBottomLeft(find.byType(UpdateBanner)).dy;
      expect(toggleTop(tester) - banner, 64);
    });

    testWidgets('fits with the largest system font', (tester) async {
      useScreen(tester, 844);
      await pumpHome(
        tester,
        scale: _largeScale,
        distribution: AppDistribution.apk,
      );

      await announceUpdate(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Текущая версия: 1.0.0'), findsOneWidget);
    });
  });

  testWidgets('the toggle and the title stay put when the status changes', (
    tester,
  ) async {
    await pumpHome(tester);
    await addSubscription(tester);
    final top = toggleTop(tester);
    final titleTop = tester.getTopLeft(find.text('Не подключено')).dy;

    for (final (view, title) in [
      (const ConnectionView(phase: ConnectionPhase.preparing), 'Подключение…'),
      (const ConnectionView(phase: ConnectionPhase.connecting), 'Подключение…'),
      (const ConnectionView(phase: ConnectionPhase.connected), 'Подключено'),
      (
        const ConnectionView(phase: ConnectionPhase.disconnecting),
        'Отключение…',
      ),
      (
        const ConnectionView(
          phase: ConnectionPhase.failed,
          issue: 'stopFailed',
        ),
        'VPN может быть включён',
      ),
    ]) {
      coordinator.state.value = view;
      await tester.pump();
      expect(toggleTop(tester), top, reason: title);
      expect(tester.getTopLeft(find.text(title)).dy, titleTop, reason: title);
    }
  });

  testWidgets('without a subscription it says where to get one', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.text('Не подключено'), findsOneWidget);
    expect(
      find.text('Откройте ссылку на подписку из бота или с сайта'),
      findsOneWidget,
    );
    expect(
      tester.widget<ConnectToggle>(find.byType(ConnectToggle)).onPressed,
      isNull,
    );
    expect(toggleState(tester), ConnectToggleState.off);
  });

  testWidgets('off with a subscription invites a tap and shows the days left', (
    tester,
  ) async {
    await pumpHome(tester);
    final expire = DateTime.now().add(const Duration(days: 46, hours: 1));
    await addSubscription(
      tester,
      expire: expire.millisecondsSinceEpoch ~/ 1000,
    );

    expect(find.text('Нажмите, чтобы подключиться'), findsOneWidget);
    expect(find.text('47 дней'), findsOneWidget);
  });

  testWidgets('hides the day count when the panel sets no expiry', (
    tester,
  ) async {
    await pumpHome(tester);
    await addSubscription(tester, expire: 0);

    expect(find.byIcon(LucideIcons.calendar).hitTestable(), findsNothing);
  });

  testWidgets('a tap moves the knob to the middle and says connecting', (
    tester,
  ) async {
    await pumpHome(tester);
    await addSubscription(tester);

    await tester.tap(find.byType(ConnectToggle));
    await tester.pump();

    expect(find.text('Подключение…'), findsOneWidget);
    expect(find.text('Выбираем самый быстрый сервер'), findsOneWidget);
    expect(toggleState(tester), ConnectToggleState.transitioning);
  });

  testWidgets('connected shows the elapsed time and the running location', (
    tester,
  ) async {
    await pumpHome(tester);
    await addSubscription(tester);
    runtime = _runtime(
      DateTime.now().subtract(const Duration(minutes: 12, seconds: 47)),
    );
    status = VpnStatus.connected;
    await tester.runAsync(() async {
      await coordinator.refresh();
      await pumpEventQueue(times: 20);
    });
    await tester.pump();

    expect(find.text('Подключено'), findsOneWidget);
    expect(toggleState(tester), ConnectToggleState.on);
    expect(find.text('Fastest'), findsOneWidget);
    expect(find.textContaining('00:12:4'), findsOneWidget);
    expect(find.textContaining('IP скрыт'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a system reconnect has its own wording', (tester) async {
    await pumpHome(tester);
    await addSubscription(tester);
    runtime = _runtime(DateTime.now());
    status = VpnStatus.connected;
    await tester.runAsync(() async {
      await coordinator.refresh();
      status = VpnStatus.connecting;
      await coordinator.refresh();
      await pumpEventQueue(times: 20);
    });
    await tester.pump();

    expect(find.text('Переподключение…'), findsOneWidget);
    expect(toggleState(tester), ConnectToggleState.transitioning);
  });

  group('error screen', () {
    const support = 'https://example.com/support';

    Future<void> fail(WidgetTester tester, String issue) async {
      coordinator.state.value = ConnectionView(
        phase: ConnectionPhase.failed,
        issue: issue,
      );
      await tester.pump();
    }

    /// Lets the connection queue run, which needs real time between frames,
    /// until [done]. Not pumpAndSettle: the connected timer ticks every second.
    Future<void> settle(WidgetTester tester, bool Function() done) async {
      for (var round = 0; round < 100 && !done(); round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.runAsync(() => pumpEventQueue(times: 50));
      await tester.pump(const Duration(milliseconds: 300));
      expect(done(), isTrue);
    }

    testWidgets('replaces the toggle and the cards and names the cause', (
      tester,
    ) async {
      await pumpHome(tester);
      await addSubscription(tester);
      await addGroup(tester, '🇩🇪 Германия');

      await fail(tester, 'insufficientHealthyServers');

      expect(find.text('Сервер не отвечает'), findsOneWidget);
      expect(
        find.text(
          'Попробуйте другую локацию или «Обход глушилок» — '
          'он работает на мобильном интернете.',
        ),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsOneWidget);
      expect(find.text('Сменить локацию'), findsOneWidget);
      expect(find.byType(ConnectToggle), findsNothing);
      expect(find.byKey(const ValueKey('home-location')), findsNothing);
      expect(find.text('Умный'), findsNothing);
    });

    testWidgets('each cause has its own title', (tester) async {
      await pumpHome(tester);
      await addSubscription(tester);

      await fail(tester, 'selectionUnavailable');
      expect(find.text('Нет доступных серверов'), findsOneWidget);

      await fail(tester, 'startFailed');
      expect(find.text('Не удалось подключиться'), findsOneWidget);
    });

    // One flow: each attempt runs through the shared Geodata queue, which
    // would stay tied to this test's fake zone for any later test. Every
    // attempt fails, so its command ends here; a successful connection is
    // covered in the controller tests.
    testWidgets('each way out of a failure tries again, without a toast', (
      tester,
    ) async {
      await pumpHome(tester);
      await addSubscription(tester);
      await addGroup(tester, '🇪🇺 AUTO | Самые быстрые', delay: 860);
      await addGroup(tester, '🇩🇪 Германия', delay: 516);
      prepareFailure = () async => throw const ConnectionResolutionException(
        ConnectionResolutionFailure.insufficientHealthyServers,
      );
      Future<void> attempt(int count) => settle(
        tester,
        () =>
            prepares == count &&
            controller.state.request == null &&
            controller.state.failure != null,
      );

      await tester.tap(find.byType(ConnectToggle));
      await attempt(1);
      expect(find.text('Сервер не отвечает'), findsOneWidget);
      expect(find.byType(ShadToast), findsNothing);

      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(toggleState(tester), ConnectToggleState.transitioning);
      await attempt(2);
      expect(find.text('Сервер не отвечает'), findsOneWidget);

      await tester.tap(find.text('Сменить локацию'));
      await tester.pumpAndSettle();
      expect(find.byType(LocationsPage), findsOneWidget);
      await tester.tap(find.text('Германия'));
      await tester.pumpAndSettle();
      await attempt(3);
      expect(find.byType(LocationsPage), findsNothing);
      final stored = await tester.runAsync(() => coordinator.configuration);
      final germany = controller.state.locations.named('Германия')!;
      expect(stored!.connection.selection.id, germany.id);
      expect(find.byType(ShadToast), findsNothing);
    });

    testWidgets('success takes the screen away', (tester) async {
      await pumpHome(tester);
      await addSubscription(tester);
      await fail(tester, 'startFailed');

      coordinator.state.value = const ConnectionView(
        phase: ConnectionPhase.connected,
      );
      await tester.pump();

      expect(find.text('Не удалось подключиться'), findsNothing);
      expect(toggleState(tester), ConnectToggleState.on);
    });

    testWidgets('«Написать в поддержку» opens the panel link', (tester) async {
      final launcher = useFakeUrlLauncher();
      await pumpHome(tester);
      await addSubscription(tester, supportUrl: support);
      await fail(tester, 'startFailed');

      await tester.tap(find.text('Написать в поддержку'));
      await tester.pump();

      expect(launcher.opened, [support]);
    });

    testWidgets('has no support button without a panel link', (tester) async {
      await pumpHome(tester);
      await addSubscription(tester);

      await fail(tester, 'startFailed');

      expect(find.text('Написать в поддержку'), findsNothing);
    });

    testWidgets('a small screen with the largest font scrolls to support', (
      tester,
    ) async {
      useScreen(tester, 568);
      await pumpHome(tester, scale: _largeScale);
      await addSubscription(tester, supportUrl: support);

      await fail(tester, 'insufficientHealthyServers');

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Написать в поддержку'));
      await tester.pumpAndSettle();
      expect(find.text('Написать в поддержку').hitTestable(), findsOneWidget);
    });
  });

  group('expired subscription', () {
    const support = 'https://t.me/launchvpn_support';
    final past =
        DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch ~/
        1000;
    final future =
        DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
        1000;

    Future<void> tapRefresh(WidgetTester tester) async {
      await tester.tap(find.text('Обновить статус'));
      await tester.runAsync(() => pumpEventQueue(times: 20));
      await tester.pump();
    }

    testWidgets(
      'an APK build offers renewal on the site instead of the toggle',
      (tester) async {
        final launcher = useFakeUrlLauncher();
        await pumpHome(tester, distribution: AppDistribution.apk);
        await addSubscription(tester, expire: past, supportUrl: support);

        expect(find.text('Подписка закончилась'), findsOneWidget);
        expect(find.byType(ConnectToggle), findsNothing);
        expect(find.text('Срок истёк'), findsNothing);
        expect(
          find.widgetWithText(TextButton, 'Обновить статус'),
          findsOneWidget,
        );

        await tester.tap(find.text('Продлить'));
        await tester.tap(find.text('Написать в поддержку'));
        await tester.pump();
        expect(launcher.opened, ['https://app.launch.tel', support]);
      },
    );

    testWidgets('a store build offers no payment', (tester) async {
      await pumpHome(tester, distribution: AppDistribution.store);
      await addSubscription(tester, expire: past);

      expect(find.text('Подписка закончилась'), findsOneWidget);
      expect(
        find.text(
          'Когда подписка снова станет активной, приложение подключится само.',
        ),
        findsOneWidget,
      );
      expect(find.text('Продлить'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Обновить статус'),
        findsOneWidget,
      );
    });

    testWidgets('without a panel link, support is the bot\'s', (tester) async {
      final launcher = useFakeUrlLauncher();
      await pumpHome(tester, distribution: AppDistribution.store);
      await addSubscription(tester, expire: past);

      await tester.tap(find.text('Написать в поддержку'));
      await tester.pump();

      expect(launcher.opened, ['https://t.me/launchbotsupport']);
    });

    testWidgets('a subscription without expiry shows the toggle', (
      tester,
    ) async {
      await pumpHome(tester);
      await addSubscription(tester, expire: 0);

      expect(find.text('Подписка закончилась'), findsNothing);
      expect(find.byType(ConnectToggle), findsOneWidget);
    });

    testWidgets('«Обновить статус» spins, then says it is not renewed yet', (
      tester,
    ) async {
      await pumpHome(tester, distribution: AppDistribution.store);
      await addSubscription(tester, expire: past);
      final loaded = Completer<SubscriptionRefreshResult>();
      refresh = (_) => loaded.future;

      await tester.tap(find.text('Обновить статус'));
      await tester.pump();
      expect(find.byType(ButtonProgressIndicator), findsOneWidget);

      loaded.complete(
        const SubscriptionRefreshResult(
          status: SubscriptionUpdateResult.success,
          count: 1,
        ),
      );
      await tester.runAsync(() => pumpEventQueue(times: 20));
      await tester.pump();

      expect(find.byType(ButtonProgressIndicator), findsNothing);
      expect(find.text('Подписка пока не продлена'), findsOneWidget);
      expect(find.text('Подписка закончилась'), findsOneWidget);
    });

    testWidgets('a renewal without VPN consent returns to the toggle', (
      tester,
    ) async {
      await pumpHome(tester, distribution: AppDistribution.apk);
      await addSubscription(tester, expire: past);
      // Only a tap may bring up the system prompt, so the renewal does not
      // connect. The controller tests cover the connection itself.
      coordinator.state.value = const ConnectionView(
        phase: ConnectionPhase.disconnected,
        issue: 'permissionRequired',
      );
      refresh = (row) async {
        await db.subscriptionDao.updateRow(
          row.copyWith(expireTimestamp: Value(future)),
        );
        return const SubscriptionRefreshResult(
          status: SubscriptionUpdateResult.success,
          count: 1,
        );
      };

      await tapRefresh(tester);

      expect(find.text('Подписка закончилась'), findsNothing);
      expect(find.text('Подписка пока не продлена'), findsNothing);
      expect(toggleState(tester), ConnectToggleState.off);
    });

    testWidgets('a failed load names the cause and keeps the screen', (
      tester,
    ) async {
      await pumpHome(tester, distribution: AppDistribution.store);
      await addSubscription(tester, expire: past);
      refresh = (_) async => const SubscriptionRefreshResult(
        status: SubscriptionUpdateResult.downloadFailed,
      );

      await tapRefresh(tester);

      expect(find.text('Не удалось загрузить подписку'), findsOneWidget);
      expect(find.text('Подписка пока не продлена'), findsNothing);
      expect(find.text('Подписка закончилась'), findsOneWidget);
    });

    testWidgets('a load another change superseded reports nothing', (
      tester,
    ) async {
      await pumpHome(tester, distribution: AppDistribution.store);
      await addSubscription(tester, expire: past);
      refresh = (_) async => const SubscriptionRefreshResult(
        status: SubscriptionUpdateResult.writeFailed,
        superseded: true,
      );

      await tapRefresh(tester);

      expect(find.byType(ShadToast), findsNothing);
    });

    testWidgets('a small screen with the largest font scrolls to support', (
      tester,
    ) async {
      useScreen(tester, 568);
      await pumpHome(
        tester,
        scale: _largeScale,
        distribution: AppDistribution.apk,
      );
      await addSubscription(tester, expire: past, supportUrl: support);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Написать в поддержку'));
      await tester.pumpAndSettle();
      expect(find.text('Написать в поддержку').hitTestable(), findsOneWidget);
    });
  });

  testWidgets(
    'a failed launch connection without a subscription asks for one',
    (tester) async {
      await pumpHome(tester);

      coordinator.state.value = const ConnectionView(
        phase: ConnectionPhase.failed,
        issue: 'startFailed',
      );
      await tester.pump();

      expect(
        find.text('Откройте ссылку на подписку из бота или с сайта'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a failed stop warns instead of claiming the VPN is off', (
    tester,
  ) async {
    await pumpHome(tester);
    await addSubscription(tester);

    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.failed,
      issue: 'stopFailed',
    );
    await tester.pump();

    expect(find.text('VPN может быть включён'), findsOneWidget);
    expect(find.text('Нажмите, чтобы отключить'), findsOneWidget);
    expect(find.text('Не подключено'), findsNothing);
    expect(toggleState(tester), ConnectToggleState.transitioning);
  });

  testWidgets('a large system font wraps the titles and clips nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHome(tester, scale: _largeScale);
    final expire = DateTime.now().add(const Duration(days: 46));
    await addSubscription(
      tester,
      expire: expire.millisecondsSinceEpoch ~/ 1000,
    );

    expect(tester.takeException(), isNull);
    for (final text in ['Не подключено', 'Нажмите, чтобы подключиться']) {
      final widget = tester.widget<Text>(find.text(text));
      expect(widget.maxLines, isNull);
      expect(widget.overflow, isNull);
    }
    final lineHeight = BrandText.screenTitle.fontSize! * _largeScale;
    expect(
      tester.getSize(find.text('Не подключено')).height,
      greaterThan(lineHeight * 1.5),
    );
    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('offers Smart and Everything through VPN, Smart first', (
    tester,
  ) async {
    await pumpHome(tester);
    await addSubscription(tester);

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Умный'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(find.text('Всё через VPN'), findsOneWidget);
  });

  testWidgets('has no preset switch without a subscription', (tester) async {
    await pumpHome(tester);

    expect(find.text('Умный'), findsNothing);
  });

  testWidgets('a tap selects the preset and saves it', (tester) async {
    await pumpHome(tester);
    await addSubscription(tester);

    await tester.tap(find.text('Всё через VPN'));
    await tester.runAsync(() => pumpEventQueue(times: 20));
    await tester.pump();

    expect(isSelected(tester, 'Всё через VPN'), Tristate.isTrue);
    await tester.runAsync(() async {
      expect(
        (await coordinator.configuration).connection.trafficMode,
        TrafficMode.allVpn,
      );
    });
  });

  testWidgets('the preset switch fits with the largest system font', (
    tester,
  ) async {
    await pumpHome(
      tester,
      scale: _largeScale,
      platform: ConnectionPlatform.android,
    );
    await addSubscription(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Приложения'), findsOneWidget);
  });

  group('Apps', () {
    final telegram = AndroidAppInfo(
      name: 'Telegram',
      packageName: 'org.telegram.messenger',
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => pumpEventQueue(times: 20));
      await tester.pumpAndSettle();
    }

    Future<void> openApps(WidgetTester tester) async {
      await pumpHome(
        tester,
        platform: ConnectionPlatform.android,
        apps: [telegram],
      );
      await addSubscription(tester);
      await tester.tap(find.text('Приложения'));
      await settle(tester);
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Назад'));
      await settle(tester);
    }

    Future<ConnectionConfiguration> stored(WidgetTester tester) async =>
        (await tester.runAsync(() => coordinator.configuration))!;

    testWidgets('is not offered on iOS', (tester) async {
      await pumpHome(tester);
      await addSubscription(tester);

      expect(find.text('Умный'), findsOneWidget);
      expect(find.text('Приложения'), findsNothing);
    });

    testWidgets('with nothing chosen opens the list first', (tester) async {
      await openApps(tester);
      expect(find.text('Приложения через VPN'), findsOneWidget);

      await tester.tap(find.text('Telegram'));
      await tester.pump();
      await leave(tester);

      expect(isSelected(tester, 'Приложения'), Tristate.isTrue);
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

    testWidgets('stays off when the list is left empty', (tester) async {
      await openApps(tester);

      await leave(tester);

      expect(isSelected(tester, 'Приложения'), Tristate.isFalse);
      expect(isSelected(tester, 'Умный'), Tristate.isTrue);
    });
  });

  group('in English', () {
    const english = Locale('en');

    testWidgets('without a subscription it says where to get one', (
      tester,
    ) async {
      await pumpHome(tester, locale: english);

      expect(find.text('Not connected'), findsOneWidget);
      expect(
        find.text('Open your subscription link from the bot or the website'),
        findsOneWidget,
      );
    });

    testWidgets('counts the days left', (tester) async {
      await pumpHome(tester, locale: english);
      final expire = DateTime.now().add(const Duration(days: 46, hours: 1));
      await addSubscription(
        tester,
        expire: expire.millisecondsSinceEpoch ~/ 1000,
      );

      expect(find.text('Tap to connect'), findsOneWidget);
      expect(find.text('47 days'), findsOneWidget);
    });

    testWidgets('an ended subscription offers renewal', (tester) async {
      await pumpHome(
        tester,
        locale: english,
        distribution: AppDistribution.apk,
      );
      final past =
          DateTime.now()
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch ~/
          1000;
      await addSubscription(tester, expire: past);

      expect(find.text('Your subscription has ended'), findsOneWidget);
      expect(find.text('Renew'), findsOneWidget);
      expect(find.text('Refresh status'), findsOneWidget);
    });
  });

  group('device limit', () {
    testWidgets(
      'signed in, the other devices are listed to remove one, and «Обновить» '
      'tries again',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final api = FakeAccountApi()
          ..loginWith(access: 'a1', refresh: 'r1')
          ..subscription('https://sub.launch.tel/a')
          ..devices([
            {
              'hwid': 'pixel-8',
              'deviceModel': 'Pixel 8',
              'platform': 'Android',
              'osVersion': '16',
            },
            {'hwid': 'iphone-13', 'deviceModel': 'iPhone 13'},
          ], max: 2);
        final account = accountServiceFor(api);
        await tester.runAsync(
          () => account.email.login(email: 'ivan@proton.me', password: 'pw'),
        );
        await pumpHome(tester, account: account);
        await addSubscription(tester, supportUrl: 'https://t.me/support');

        deviceLimit.value = true;
        await tester.runAsync(() => pumpEventQueue(times: 20));
        await tester.pumpAndSettle();

        expect(find.text('Лимит устройств'), findsOneWidget);
        expect(
          find.text(
            'На подписке 2 устройства из 2. Удалите одно, чтобы подключить '
            'этот телефон.',
          ),
          findsOneWidget,
        );
        expect(find.byType(ConnectToggle), findsNothing);
        expect(find.byIcon(LucideIcons.trash2), findsNWidgets(2));
        expect(find.text('Написать в поддержку'), findsOneWidget);

        await tester.tap(find.text('Pixel 8'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Удалить устройство'));
        await tester.runAsync(() => pumpEventQueue(times: 20));
        await tester.pumpAndSettle();
        expect(find.text('Pixel 8 удалён, место освободилось'), findsOneWidget);
        expect(find.text('Pixel 8'), findsNothing);

        final refreshed = <String>[];
        refresh = (row) async {
          refreshed.add(row.url);
          return const SubscriptionRefreshResult(
            status: SubscriptionUpdateResult.success,
          );
        };
        await tester.tap(find.text('Обновить'));
        await tester.runAsync(() => pumpEventQueue(times: 20));
        await tester.pumpAndSettle();
        expect(refreshed, ['https://sub.launch.tel/a']);

        deviceLimit.value = false;
        await tester.pumpAndSettle();
        expect(find.byType(ConnectToggle), findsOneWidget);
      },
    );

    testWidgets('from a link only, support is the one way out', (tester) async {
      await pumpHome(tester);
      await addSubscription(tester, supportUrl: 'https://t.me/support');

      deviceLimit.value = true;
      await tester.pumpAndSettle();

      expect(find.text('Лимит устройств'), findsOneWidget);
      expect(
        find.text(
          'На подписке заняты все места для устройств. Удалите одно в боте '
          'или в кабинете на app.launch.tel, чтобы подключить этот телефон.',
        ),
        findsOneWidget,
      );
      expect(find.text('Написать в поддержку'), findsOneWidget);
      expect(find.text('Обновить'), findsNothing);
      expect(find.byIcon(LucideIcons.trash2), findsNothing);
    });

    testWidgets('without a panel link, support is the bot\'s', (tester) async {
      final launcher = useFakeUrlLauncher();
      await pumpHome(tester);
      await addSubscription(tester);

      deviceLimit.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Написать в поддержку'));
      await tester.pump();

      expect(launcher.opened, ['https://t.me/launchbotsupport']);
    });
  });
}
