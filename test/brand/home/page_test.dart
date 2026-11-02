import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:country_flags/country_flags.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/home/page.dart';
import 'package:onexray/brand/home/toggle.dart';
import 'package:onexray/brand/locations/page.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _largeScale = 3.0;

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
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late HomeController controller;
  late StreamController<VpnStatus> statusEvents;
  late Completer<HostConnection> start;
  var status = VpnStatus.disconnected;
  ConnectionRuntime? runtime;
  var sweeps = 0;

  Future<void> pumpHome(WidgetTester tester, {double scale = 1}) async {
    final bus = AppEventBus();
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
        prepare: (_, _) async => _runtime(DateTime(2026)),
        start: (_) => start.future,
        stop: () async => const HostConnection(VpnStatus.disconnected),
      );
      await coordinator.initialize(registerReferences: false);
    });
    addTearDown(coordinator.dispose);
    controller = HomeController(
      database: db,
      coordinator: coordinator,
      pingLocations: (_, {isCancelled}) async => sweeps++,
      dismissAnnounce: db.subscriptionDao.dismissAnnounce,
    );
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
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
        home: HomePage(controller: controller),
      ),
    );
    await tester.runAsync(() => pumpEventQueue(times: 20));
    await tester.pump();
  }

  Future<void> addSubscription(WidgetTester tester, {int? expire}) async {
    await tester.runAsync(() async {
      await db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'LaunchVPN',
          url: 'https://sub.launch.tel/a',
          timestamp: DateTime(2026),
          mode: Value(SubscriptionMode.providerManaged.name),
          expireTimestamp: Value(expire),
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
    sweeps = 0;
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
          issue: 'startFailed',
        ),
        'Не подключено',
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

  testWidgets('a failed attempt says so and keeps the knob off', (
    tester,
  ) async {
    await pumpHome(tester);
    await addSubscription(tester);

    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.failed,
      issue: 'startFailed',
    );
    await tester.pump();

    expect(find.text('Не подключено'), findsOneWidget);
    expect(
      find.text('Не удалось подключиться. Нажмите, чтобы попробовать ещё раз'),
      findsOneWidget,
    );
    expect(toggleState(tester), ConnectToggleState.off);
  });

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

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Всё через VPN'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
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
    await pumpHome(tester, scale: _largeScale);
    await addSubscription(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Всё через VPN'), findsOneWidget);
  });
}
