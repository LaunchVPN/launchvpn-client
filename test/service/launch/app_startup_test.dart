import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/launch/app_startup.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late StreamController<VpnStatus> statusEvents;
  late Completer<HostConnection> started;
  late int starts;

  // PreferencesKey keeps the first platform it sees, so tests share one store.
  setUpAll(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    statusEvents = StreamController<VpnStatus>.broadcast(sync: true);
    started = Completer();
    starts = 0;
    coordinator = ConnectionCoordinator(
      database: db,
      statusEvents: statusEvents.stream,
      observeStatus: () async {},
      disposeStatus: () {},
      readRuntime: () async => null,
      inspect: (current, {observedStatus}) async => HostConnection(
        observedStatus ?? VpnStatus.disconnected,
        runtime: current,
      ),
      prepare: (_, _) async => _runtime(),
      start: (_) {
        starts++;
        return started.future;
      },
      stop: () async => const HostConnection(VpnStatus.disconnected),
    );
    await coordinator.initialize(registerReferences: false);
  });

  tearDown(() async {
    if (!started.isCompleted) {
      started.complete(const HostConnection(VpnStatus.disconnected));
    }
    await pumpEventQueue(times: 20);
    coordinator.dispose();
    await statusEvents.close();
    await db.close();
  });

  Future<AppStartupService> launch({required bool connectOnLaunch}) async {
    await PreferencesKey().saveConnectOnAppLaunch(connectOnLaunch);
    final startup = AppStartupService.forTesting(coordinator: coordinator);
    await startup.prepare();
    return startup;
  }

  test(
    'the setting starts a connection and startup does not wait for it',
    () async {
      final startup = await launch(connectOnLaunch: true);

      // Would never finish if startup waited for the tunnel.
      await startup.handleServicesReady();
      await pumpEventQueue(times: 20);

      expect(starts, 1);
      expect(started.isCompleted, isFalse);
    },
  );

  test('without the setting nothing connects', () async {
    final startup = await launch(connectOnLaunch: false);

    await startup.handleServicesReady();
    await pumpEventQueue(times: 20);

    expect(starts, 0);
  });

  test('a suppressed launch does not connect', () async {
    final startup = await launch(connectOnLaunch: true);
    startup.suppressConnectOnAppLaunch();

    await startup.handleServicesReady();
    await pumpEventQueue(times: 20);

    expect(starts, 0);
  });

  test('a failed connection does not fail startup', () async {
    final startup = await launch(connectOnLaunch: true);

    await startup.handleServicesReady();
    started.complete(const HostConnection(VpnStatus.disconnected));
    await startup.launchConnection;

    expect(coordinator.state.value.failed, isTrue);
  });
}
