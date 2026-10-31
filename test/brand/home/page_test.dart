import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/home/page.dart';
import 'package:onexray/brand/home/toggle.dart';
import 'package:onexray/brand/theme.dart';
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
    controller = HomeController(database: db, coordinator: coordinator);
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

  ConnectToggleState toggleState(WidgetTester tester) =>
      tester.widget<ConnectToggle>(find.byType(ConnectToggle)).state;

  setUp(() {
    status = VpnStatus.disconnected;
    runtime = null;
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

    expect(find.byIcon(LucideIcons.calendar), findsNothing);
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
    expect(find.text('AUTO | Fastest'), findsOneWidget);
    expect(find.textContaining('00:12:4'), findsOneWidget);
    expect(find.textContaining('IP скрыт'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a system reconnect has its own wording', (tester) async {
    await pumpHome(tester);
    await addSubscription(tester);
    runtime = _runtime(DateTime.now());
    status = VpnStatus.connecting;
    await tester.runAsync(() async {
      await coordinator.refresh();
      await pumpEventQueue(times: 20);
    });
    await tester.pump();

    expect(find.text('Переподключение…'), findsOneWidget);
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
}
