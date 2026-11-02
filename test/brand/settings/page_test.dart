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
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/shared/share/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final class _Store extends InMemorySharedPreferencesAsync {
  _Store() : super.empty();

  bool failReads = false;

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async {
    if (failReads) throw StateError('unreadable');
    return super.getBool(key, options);
  }
}

ConnectionRuntime _runtime() => ConnectionRuntime.create(
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
  startedAt: DateTime(2026),
);

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late HomeController controller;
  late Completer<HostConnection> start;
  var status = VpnStatus.disconnected;
  ConnectionRuntime? runtime;

  // PreferencesKey keeps the first platform it sees, so tests share one store.
  final store = _Store();
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = store);

  setUp(() async {
    store.failReads = false;
    await SharedPreferencesAsync().clear();
    start = Completer();
    status = VpnStatus.disconnected;
    runtime = null;
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => pumpEventQueue(times: 20));
    await tester.pumpAndSettle();
  }

  Future<void> pumpRouter(WidgetTester tester) async {
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
      shareService: share,
      initializeServices: (_) => share.init(),
      openLink: (_, _) async {},
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(BrandApp(routerConfig: router));
    await settle(tester);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
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
        start: (_) => start.future,
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
    controller = HomeController(
      database: db,
      coordinator: coordinator,
      pingLocations: (_, {isCancelled}) async {},
      dismissAnnounce: db.subscriptionDao.dismissAnnounce,
    );
    addTearDown(controller.close);
    await pumpRouter(tester);
  }

  Future<void> openTab(WidgetTester tester, int index) async {
    await tester.tap(find.byType(NavigationDestination).at(index));
    await settle(tester);
  }

  testWidgets('the mode row follows a choice made on Home', (tester) async {
    await pumpApp(tester);

    await openTab(tester, 1);
    expect(find.text('Режим'), findsOneWidget);
    expect(find.text('Умный'), findsOneWidget);

    await openTab(tester, 0);
    await tester.tap(find.text('Всё через VPN'));
    await settle(tester);

    await openTab(tester, 1);
    expect(find.text('Всё через VPN'), findsOneWidget);
    expect(find.text('Умный'), findsNothing);
  });

  group('connect at launch', () {
    const title = 'Подключать при запуске';

    Tristate toggled(WidgetTester tester) => tester
        .getSemantics(find.bySemanticsLabel(title))
        .flagsCollection
        .isToggled;

    testWidgets('is off until the user turns it on', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 1);

      expect(toggled(tester), Tristate.isFalse);
    });

    testWidgets('a tap anywhere on the row turns it on and off', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 1);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isTrue);

      await tester.tap(find.byType(ShadSwitch));
      await settle(tester);
      expect(toggled(tester), Tristate.isFalse);
    });

    testWidgets('an unreadable value reads as off and can still be changed', (
      tester,
    ) async {
      store.failReads = true;
      await pumpApp(tester);
      await openTab(tester, 1);
      expect(toggled(tester), Tristate.isFalse);

      await tester.tap(find.text(title));
      await settle(tester);
      expect(toggled(tester), Tristate.isTrue);
    });

    test('a second tap during a save is ignored', () async {
      final settings = SettingsController();
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
      await openTab(tester, 1);
      await tester.tap(find.text(title));
      await settle(tester);

      await tester.pumpWidget(const SizedBox());
      await pumpRouter(tester);
      await openTab(tester, 1);

      expect(toggled(tester), Tristate.isTrue);
    });
  });

  group('the preset screen', () {
    Future<void> openPresets(WidgetTester tester) async {
      await openTab(tester, 1);
      await tester.tap(find.text('Режим'));
      await settle(tester);
    }

    Tristate selected(WidgetTester tester, String label) => tester
        .getSemantics(find.bySemanticsLabel(RegExp('^$label')))
        .flagsCollection
        .isSelected;

    testWidgets('marks the current mode and offers both presets', (
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
        TrafficMode.allVpn,
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
}
