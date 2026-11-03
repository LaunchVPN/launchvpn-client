import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

ConnectionRuntime _runtime([ConnectionConfiguration? configuration]) =>
    ConnectionRuntime.create(
      configuration: configuration ?? ConnectionConfiguration(),
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
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StreamController<VpnStatus> statusEvents;
  late ConnectionCoordinator coordinator;
  late HomeController controller;
  late Completer<HostConnection> start;
  late Completer<HostConnection> stop;
  late Future<void> Function() prepareFailure;
  late ConnectionRuntime runtime;
  late List<Object> failures;
  late List<List<int>> sweeps;
  late List<bool Function()?> sweepCancels;
  late Future<void> Function() sweep;
  late Future<SubscriptionRefreshResult> Function(SubscriptionData) refresh;
  var status = VpnStatus.disconnected;
  var stopCalls = 0;

  Future<void> settle() => pumpEventQueue(times: 50);

  setUp(() async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    status = VpnStatus.disconnected;
    start = Completer();
    stop = Completer();
    prepareFailure = () async {};
    failures = [];
    sweeps = [];
    sweepCancels = [];
    sweep = () async {};
    refresh = (_) async => const SubscriptionRefreshResult(
      status: SubscriptionUpdateResult.success,
    );
    stopCalls = 0;
    runtime = _runtime();
    statusEvents = StreamController<VpnStatus>.broadcast(sync: true);
    addTearDown(statusEvents.close);
    coordinator = ConnectionCoordinator(
      database: db,
      statusEvents: statusEvents.stream,
      observeStatus: () async {},
      disposeStatus: () {},
      readRuntime: () async =>
          status == VpnStatus.disconnected ? null : runtime,
      inspect: (current, {observedStatus}) async =>
          HostConnection(observedStatus ?? status, runtime: current),
      prepare: (configuration, _) async {
        await prepareFailure();
        return runtime = _runtime(configuration);
      },
      start: (_) => start.future,
      stop: () {
        stopCalls++;
        return stop.future;
      },
    );
    addTearDown(coordinator.dispose);
    await coordinator.initialize(registerReferences: false);
    controller = HomeController(
      database: db,
      coordinator: coordinator,
      pingLocations: (rows, {isCancelled}) {
        sweeps.add([for (final row in rows) row.id]);
        sweepCancels.add(isCancelled);
        return sweep();
      },
      refreshSubscription: (row) => refresh(row),
    );
    addTearDown(controller.close);
    await controller.initialize();
    await settle();
  });

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      failures.add(error);
    }
  }

  Future<void> addSubscription({int? expire}) async {
    await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'LaunchVPN',
        url: 'https://sub.launch.tel/a',
        timestamp: DateTime(2026),
        mode: Value(SubscriptionMode.providerManaged.name),
        expireTimestamp: Value(expire),
        userInfoUpdatedAt: Value(DateTime.utc(2026)),
      ),
    );
    await settle();
  }

  /// Ends every connection it starts: a start left waiting would hold the shared
  /// Geodata queue from the next test.
  Future<void> connectFully({Future<void> Function()? whileConnecting}) async {
    final toggled = controller.toggle(run, explain: _explainNever);
    await settle();
    await whileConnecting?.call();
    status = VpnStatus.connected;
    start.complete(HostConnection(VpnStatus.connected, runtime: runtime));
    await toggled;
    await settle();
  }

  group('toggle', () {
    test('connects and reaches connected', () async {
      await addSubscription();

      final toggled = controller.toggle(run, explain: _explainNever);
      await settle();
      expect(controller.state.status, HomeStatus.connecting);

      status = VpnStatus.connected;
      start.complete(HostConnection(VpnStatus.connected, runtime: runtime));
      await toggled;
      await settle();

      expect(controller.state.status, HomeStatus.connected);
      expect(failures, isEmpty);
    });

    test(
      'shows connecting immediately, before the coordinator reports',
      () async {
        await addSubscription();

        unawaited(controller.toggle(run, explain: _explainNever));

        expect(controller.state.status, HomeStatus.connecting);
      },
    );

    test('a tap while connecting cancels and returns to off', () async {
      await addSubscription();
      final connecting = controller.toggle(run, explain: _explainNever);
      await settle();
      expect(coordinator.state.value.phase, ConnectionPhase.connecting);

      stop.complete(const HostConnection(VpnStatus.disconnected));
      await controller.toggle(run, explain: _explainNever);
      await connecting;
      expect(failures, hasLength(1));
      expect(failures.single, isA<ConnectionHostException>());
      await settle();

      expect(controller.state.status, HomeStatus.off);
    });

    test('a tap while connected disconnects', () async {
      await addSubscription();
      status = VpnStatus.connected;
      await coordinator.refresh();
      await settle();
      expect(controller.state.status, HomeStatus.connected);

      final disconnecting = controller.toggle(run, explain: _explainNever);
      expect(controller.state.status, HomeStatus.disconnecting);

      status = VpnStatus.disconnected;
      stop.complete(const HostConnection(VpnStatus.disconnected));
      await disconnecting;
      await settle();

      expect(controller.state.status, HomeStatus.off);
    });

    test('a failed connection is reported once and shown as failed', () async {
      await addSubscription();
      prepareFailure = () async => throw const ConnectionHostException('x');

      await controller.toggle(run, explain: _explainNever);
      await settle();

      expect(failures, hasLength(1));
      expect(controller.state.status, HomeStatus.failed);
    });

    test('names why the attempt failed', () async {
      await addSubscription();
      final expected = {
        ConnectionResolutionFailure.insufficientHealthyServers:
            HomeFailure.serverSilent,
        ConnectionResolutionFailure.probeFailed: HomeFailure.other,
        ConnectionResolutionFailure.finalExitUnavailable: HomeFailure.other,
        ConnectionResolutionFailure.selectionUnavailable: HomeFailure.noServers,
        ConnectionResolutionFailure.insufficientCandidates: HomeFailure.other,
        ConnectionResolutionFailure.invalidSettings: HomeFailure.other,
      };
      for (final MapEntry(key: reason, value: failure) in expected.entries) {
        prepareFailure = () async =>
            throw ConnectionResolutionException(reason);

        await controller.toggle(run, explain: _explainNever);
        await settle();

        expect(controller.state.failure, failure, reason: reason.name);
      }
    });

    test('the error screen explains its own error, not an older one', () async {
      await addSubscription();
      prepareFailure = () async => throw const ConnectionResolutionException(
        ConnectionResolutionFailure.insufficientHealthyServers,
      );

      await controller.toggle(run, explain: _explainNever);
      await settle();

      expect(controller.state.explains(failures.single), isTrue);
      expect(controller.state.explains(StateError('other')), isFalse);
    });

    test('a generic failure keeps the toast that names its cause', () async {
      await addSubscription();
      prepareFailure = () async => throw const ConnectionHostException('x');

      await controller.toggle(run, explain: _explainNever);
      await settle();

      expect(controller.state.failure, HomeFailure.other);
      expect(controller.state.explains(failures.single), isFalse);
    });

    test('a refused VPN permission is not a failure', () async {
      await addSubscription();

      coordinator.state.value = ConnectionView(
        phase: ConnectionPhase.failed,
        issue: 'permissionRequired',
        permission: PlatformPermissionResult(
          kind: PlatformPermissionKind.androidVpn,
          state: PlatformPermissionState.denied,
        ),
      );

      expect(controller.state.failure, isNull);
      expect(controller.state.status, HomeStatus.off);
    });

    test('a cancelled attempt is not a failure', () async {
      await addSubscription();
      final connecting = controller.toggle(run, explain: _explainNever);
      await settle();
      stop.complete(const HostConnection(VpnStatus.disconnected));
      await controller.toggle(run, explain: _explainNever);
      await connecting;
      await settle();

      expect(controller.state.failure, isNull);
      expect(controller.state.explains(failures.single), isFalse);
    });

    test('does nothing without a subscription', () async {
      await controller.toggle(run, explain: _explainNever);
      await settle();

      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(controller.state.canToggle, isFalse);
      expect(controller.state.status, HomeStatus.off);
    });
  });

  group('system transitions', () {
    test(
      'a running session falling back to connecting is a reconnect',
      () async {
        await addSubscription();
        status = VpnStatus.connected;
        await coordinator.refresh();
        await settle();

        status = VpnStatus.connecting;
        statusEvents.add(VpnStatus.connecting);
        await settle();

        expect(controller.state.status, HomeStatus.reconnecting);

        status = VpnStatus.connected;
        statusEvents.add(VpnStatus.connected);
        await settle();

        expect(controller.state.status, HomeStatus.connected);
      },
    );

    test('a tap during a reconnect stops the VPN', () async {
      await addSubscription();
      status = VpnStatus.connected;
      await coordinator.refresh();
      await settle();
      status = VpnStatus.connecting;
      statusEvents.add(VpnStatus.connecting);
      await settle();
      expect(controller.state.status, HomeStatus.reconnecting);

      status = VpnStatus.disconnected;
      stop.complete(const HostConnection(VpnStatus.disconnected));
      await controller.toggle(run, explain: _explainNever);
      await settle();

      expect(controller.state.status, HomeStatus.off);
    });

    test('a start from outside the app is not a reconnect', () async {
      await addSubscription();
      status = VpnStatus.connecting;
      await coordinator.refresh();
      await settle();

      expect(controller.state.status, HomeStatus.connecting);
    });

    test('a tap stops a start from outside the app', () async {
      await addSubscription();
      status = VpnStatus.connecting;
      await coordinator.refresh();
      await settle();

      status = VpnStatus.disconnected;
      stop.complete(const HostConnection(VpnStatus.disconnected));
      await controller.toggle(run, explain: _explainNever);
      await settle();

      expect(controller.state.status, HomeStatus.off);
    });

    test('a tap stops a native start with no session data', () async {
      await addSubscription();
      coordinator.state.value = const ConnectionView(
        phase: ConnectionPhase.connecting,
      );
      expect(controller.state.status, HomeStatus.connecting);

      stop.complete(const HostConnection(VpnStatus.disconnected));
      await controller.toggle(run, explain: _explainNever);
      await settle();

      expect(stopCalls, 1);
      expect(controller.state.status, HomeStatus.off);
    });

    test('a failed disconnect never claims the VPN is off', () async {
      await addSubscription();
      status = VpnStatus.connected;
      await coordinator.refresh();
      await settle();

      final stopping = controller.toggle(run, explain: _explainNever);
      await settle();
      stop.completeError(StateError('no answer'));
      await stopping;
      await settle();

      expect(failures, hasLength(1));
      expect(controller.state.status, HomeStatus.uncertain);
      expect(controller.state.canToggle, isTrue);
    });
  });

  group('subscription data', () {
    test('names the server in use', () async {
      await addSubscription();
      status = VpnStatus.connected;
      await coordinator.refresh();
      await settle();

      expect(controller.state.location?.name, 'Fastest');
    });

    test('counts the days left, rounding a partial day up', () async {
      final now = DateTime.utc(2026, 11, 1);
      final expire = now.add(const Duration(days: 46, hours: 1));
      await addSubscription(expire: expire.millisecondsSinceEpoch ~/ 1000);

      expect(controller.state.daysLeft(now), 47);
    });

    test('has no day count without an expiry date', () async {
      await addSubscription(expire: 0);

      expect(controller.state.daysLeft(DateTime.utc(2026)), isNull);
    });

    test('an expired subscription has zero days left', () async {
      await addSubscription(
        expire: DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000,
      );

      expect(controller.state.daysLeft(DateTime.utc(2026, 2)), 0);
    });
  });

  group('expiry', () {
    int epoch(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
    final past = epoch(DateTime.now().subtract(const Duration(days: 1)));
    final future = epoch(DateTime.now().add(const Duration(days: 30)));

    Future<void> setExpiry(int expire) async {
      final row = (await db.subscriptionDao.allRows).single;
      await db.subscriptionDao.updateRow(
        row.copyWith(expireTimestamp: Value(expire)),
      );
      await settle();
    }

    /// Ends the connection a renewal starts, so no start is left waiting.
    Future<void> finishConnecting() async {
      status = VpnStatus.connected;
      start.complete(HostConnection(VpnStatus.connected, runtime: runtime));
      await settle();
    }

    test('a past expiry ends the subscription, none never does', () async {
      await addSubscription(expire: 0);
      expect(controller.state.expired, isFalse);

      await setExpiry(past);

      expect(controller.state.expired, isTrue);
    });

    test('turns off a tunnel that is running when the time runs out', () async {
      await addSubscription(expire: future);
      await connectFully();
      stop.complete(const HostConnection(VpnStatus.disconnected));

      await setExpiry(past);

      expect(stopCalls, 1);
      expect(controller.state.status, HomeStatus.off);
    });

    test('a failed automatic disconnect keeps the toggle to retry', () async {
      await addSubscription(expire: future);
      await connectFully();

      await setExpiry(past);
      stop.completeError(StateError('no answer'));
      await settle();

      expect(controller.state.status, HomeStatus.uncertain);
      expect(controller.state.showsExpired, isFalse);
    });

    test('turns off a tunnel started from outside after expiry', () async {
      await addSubscription(expire: past);
      stop.complete(const HostConnection(VpnStatus.disconnected));

      status = VpnStatus.connected;
      await coordinator.refresh();
      await settle();

      expect(stopCalls, 1);
    });

    test('connects once the subscription is renewed', () async {
      await addSubscription(expire: past);

      await setExpiry(future);

      expect(controller.state.expired, isFalse);
      expect(controller.state.status, HomeStatus.connecting);
      await finishConnecting();
      expect(controller.state.status, HomeStatus.connected);
    });

    test('removing an expired subscription does not connect', () async {
      await addSubscription(expire: past);

      await db.subscriptionDao.deleteRow(
        (await db.subscriptionDao.allRows).single.id,
      );
      await settle();

      expect(controller.state.expired, isFalse);
      expect(controller.state.status, HomeStatus.off);
    });

    test('a refresh of an active subscription does not connect', () async {
      await addSubscription(expire: future);

      await setExpiry(future + 60);

      expect(controller.state.status, HomeStatus.off);
    });

    test('refreshStatus loads the subscription and reports it', () async {
      await addSubscription(expire: past);
      var refreshing = false;
      refresh = (_) async {
        refreshing = controller.state.refreshing;
        return const SubscriptionRefreshResult(
          status: SubscriptionUpdateResult.success,
          count: 1,
        );
      };

      final result = await controller.refreshStatus();

      expect(refreshing, isTrue);
      expect(controller.state.refreshing, isFalse);
      expect(result!.success, isTrue);
      expect(controller.state.expired, isTrue);
    });

    test('refreshStatus that finds a renewal connects at once', () async {
      await addSubscription(expire: past);
      refresh = (row) async {
        await db.subscriptionDao.updateRow(
          row.copyWith(expireTimestamp: Value(future)),
        );
        return const SubscriptionRefreshResult(
          status: SubscriptionUpdateResult.success,
          count: 1,
        );
      };

      await controller.refreshStatus();

      expect(controller.state.expired, isFalse);
      expect(controller.state.status, HomeStatus.connecting);
      await finishConnecting();
    });

    test('a failed refreshStatus keeps the subscription expired', () async {
      await addSubscription(expire: past);
      refresh = (_) async => const SubscriptionRefreshResult(
        status: SubscriptionUpdateResult.downloadFailed,
      );

      final result = await controller.refreshStatus();

      expect(result!.success, isFalse);
      expect(controller.state.expired, isTrue);
      expect(controller.state.status, HomeStatus.off);
    });
  });

  group('location', () {
    late int fastest;
    late int germany;

    Future<int> addGroup(String name) async {
      final id = await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: name,
          type: CoreConfigType.Remnawave.name,
          tags: '',
          delay: PingDelayConstants.unknown,
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
      await settle();
      return id;
    }

    Future<ServerSelection> stored() async =>
        (await coordinator.configuration).connection.selection;

    setUp(() async {
      await addSubscription();
      fastest = await addGroup('🇪🇺 AUTO | Самые быстрые');
      germany = await addGroup('🇩🇪 Германия');
    });

    test('is the first group until the user chooses', () {
      expect(controller.state.location?.id, fastest);
    });

    test(
      'while off, the choice is saved without touching the tunnel',
      () async {
        await controller.selectLocation(
          controller.state.locations.withId(germany)!,
          run,
          explain: _explainNever,
        );

        expect(controller.state.location?.name, 'Германия');
        expect((await stored()).id, germany);
        expect((await stored()).kind, SelectionKind.server);
        expect(stopCalls, 0);
        expect(failures, isEmpty);
      },
    );

    test('survives a restart of the screen', () async {
      await controller.selectLocation(
        controller.state.locations.withId(germany)!,
        run,
        explain: _explainNever,
      );

      final reopened = HomeController(database: db, coordinator: coordinator);
      addTearDown(reopened.close);
      await reopened.initialize();
      await settle();

      expect(reopened.state.location?.name, 'Германия');
    });

    test('while connected, it reconnects at once and says so', () async {
      await connectFully();
      start = Completer();

      final selecting = controller.selectLocation(
        controller.state.locations.withId(germany)!,
        run,
        explain: _explainNever,
      );
      await settle();
      expect(controller.state.status, HomeStatus.reconnecting);
      expect(controller.state.location?.name, 'Германия');
      expect(stopCalls, 1);

      stop.complete(const HostConnection(VpnStatus.disconnected));
      await settle();
      status = VpnStatus.connected;
      start.complete(HostConnection(VpnStatus.connected, runtime: runtime));
      await selecting;
      await settle();

      expect(controller.state.status, HomeStatus.connected);
      expect((await stored()).id, germany);
      expect(failures, isEmpty);
    });

    test('a failed reconnect keeps the choice for the next attempt', () async {
      await connectFully();
      prepareFailure = () async => throw StateError('no route');
      stop = Completer()
        ..complete(const HostConnection(VpnStatus.disconnected));

      await controller.selectLocation(
        controller.state.locations.withId(germany)!,
        run,
        explain: _explainNever,
      );
      await settle();

      expect(failures, isNotEmpty);
      expect((await stored()).id, germany);
    });

    test('after a failed attempt, the choice connects through it', () async {
      prepareFailure = () async => throw StateError('no route');
      await controller.toggle(run, explain: _explainNever);
      await settle();
      expect(controller.state.status, HomeStatus.failed);
      prepareFailure = () async {};

      final selecting = controller.selectLocation(
        controller.state.locations.withId(germany)!,
        run,
        explain: _explainNever,
      );
      await settle();
      expect(controller.state.status, HomeStatus.connecting);

      status = VpnStatus.connected;
      start.complete(HostConnection(VpnStatus.connected, runtime: runtime));
      await selecting;
      await settle();

      expect(controller.state.status, HomeStatus.connected);
      expect(controller.state.failure, isNull);
      expect((await stored()).id, germany);
    });

    test('after a failed attempt, the same location connects again', () async {
      prepareFailure = () async => throw StateError('no route');
      await controller.toggle(run, explain: _explainNever);
      await settle();
      prepareFailure = () async {};

      final selecting = controller.selectLocation(
        controller.state.locations.withId(fastest)!,
        run,
        explain: _explainNever,
      );
      await settle();
      expect(controller.state.status, HomeStatus.connecting);

      status = VpnStatus.connected;
      start.complete(HostConnection(VpnStatus.connected, runtime: runtime));
      await selecting;
      await settle();

      expect(controller.state.status, HomeStatus.connected);
    });

    test(
      'after a failure, the shown location replaces a missing one',
      () async {
        await db.connectionConfigDao.commit(
          configurationJson: ConnectionConfiguration(
            connection: ConnectionSettings(
              selection: const ServerSelection.server(99999),
            ),
          ).encode(),
        );
        await settle();
        expect(controller.state.location?.id, fastest);
        prepareFailure = () async => throw const ConnectionResolutionException(
          ConnectionResolutionFailure.selectionUnavailable,
        );
        await controller.toggle(run, explain: _explainNever);
        await settle();
        expect(controller.state.status, HomeStatus.failed);
        prepareFailure = () async {};

        final selecting = controller.selectLocation(
          controller.state.locations.withId(fastest)!,
          run,
          explain: _explainNever,
        );
        await settle();
        expect((await stored()).id, fastest);
        expect(controller.state.status, HomeStatus.connecting);

        status = VpnStatus.connected;
        start.complete(HostConnection(VpnStatus.connected, runtime: runtime));
        await selecting;
      },
    );

    test('cannot change while a connection is in progress', () async {
      await connectFully(
        whileConnecting: () async {
          await controller.selectLocation(
            controller.state.locations.withId(germany)!,
            run,
            explain: _explainNever,
          );
          expect((await stored()).kind, SelectionKind.automatic);
        },
      );
    });

    test('shows a selection left on a kept row as its fresh copy', () async {
      await db.connectionConfigDao.commit(
        configurationJson: ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: ServerSelection.server(germany),
          ),
        ).encode(),
      );
      final fresh = await addGroup('🇩🇪 Германия');
      await settle();

      expect(controller.state.location?.id, fresh);
      expect(controller.state.location?.name, 'Германия');
    });

    test('follows a selection a refresh has moved', () async {
      final fresh = await addGroup('🇩🇪 Германия');
      await db.connectionConfigDao.commit(
        configurationJson: ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: ServerSelection.server(fresh),
          ),
        ).encode(),
      );
      await settle();

      expect(controller.state.location?.id, fresh);
      expect(controller.state.location?.name, 'Германия');
    });

    group('ping', () {
      test('measures every listed group while off', () async {
        await controller.measureLocations();

        expect(sweeps, [
          [fastest, germany],
        ]);
      });

      test('measures nothing while connected', () async {
        await connectFully();

        await controller.measureLocations();

        expect(sweeps, isEmpty);
      });

      test('runs one sweep at a time', () async {
        final running = Completer<void>();
        sweep = () => running.future;

        unawaited(controller.measureLocations());
        await controller.measureLocations();
        expect(sweeps, hasLength(1));

        running.complete();
        await settle();
        await controller.measureLocations();
        expect(sweeps, hasLength(2));
      });

      test('a sweep stops as soon as the tunnel starts', () async {
        await controller.measureLocations();
        expect(sweepCancels.single!(), isFalse);

        await connectFully(
          whileConnecting: () async {
            expect(sweepCancels.single!(), isTrue);
          },
        );
      });

      test('a failed sweep is not the user\'s problem', () async {
        sweep = () async => throw StateError('core is busy');

        await controller.measureLocations();
        await controller.measureLocations();

        expect(sweeps, hasLength(2));
        expect(failures, isEmpty);
      });
    });
  });

  group('preset', () {
    Future<void> connect() async {
      await addSubscription();
      await connectFully();
      start = Completer();
    }

    Future<TrafficMode> stored() async =>
        (await coordinator.configuration).connection.trafficMode;

    test('takes no choice before the saved preset is known', () async {
      await controller.selectPreset(TrafficMode.allVpn, run);

      final reopened = HomeController(database: db, coordinator: coordinator);
      addTearDown(reopened.close);
      expect(reopened.state.preset, isNull);

      await reopened.selectPreset(TrafficMode.smart, run);

      expect(await stored(), TrafficMode.allVpn);
    });

    test('is Smart until the user chooses', () {
      expect(controller.state.preset, TrafficMode.smart);
    });

    test(
      'while off, the choice is saved without touching the tunnel',
      () async {
        await controller.selectPreset(TrafficMode.allVpn, run);

        expect(controller.state.preset, TrafficMode.allVpn);
        expect(await stored(), TrafficMode.allVpn);
        expect(stopCalls, 0);
        expect(failures, isEmpty);
      },
    );

    test('survives a restart of the screen', () async {
      await controller.selectPreset(TrafficMode.allVpn, run);

      final reopened = HomeController(database: db, coordinator: coordinator);
      addTearDown(reopened.close);
      await reopened.initialize();

      expect(reopened.state.preset, TrafficMode.allVpn);
    });

    test('while connected, it reconnects at once and says so', () async {
      await connect();

      final selecting = controller.selectPreset(TrafficMode.allVpn, run);
      expect(controller.state.status, HomeStatus.reconnecting);
      expect(controller.state.preset, TrafficMode.allVpn);
      await settle();
      expect(stopCalls, 1);
      expect(controller.state.status, HomeStatus.reconnecting);

      status = VpnStatus.disconnected;
      stop.complete(const HostConnection(VpnStatus.disconnected));
      await settle();
      expect(controller.state.status, HomeStatus.reconnecting);

      status = VpnStatus.connected;
      start.complete(HostConnection(VpnStatus.connected, runtime: runtime));
      await selecting;
      await settle();

      expect(controller.state.status, HomeStatus.connected);
      expect(await stored(), TrafficMode.allVpn);
      expect(failures, isEmpty);
    });

    test('a failed reconnect keeps the choice for the next attempt', () async {
      await connect();
      prepareFailure = () async => throw const ConnectionHostException('x');
      stop.complete(const HostConnection(VpnStatus.disconnected));

      await controller.selectPreset(TrafficMode.allVpn, run);
      await settle();

      expect(failures, hasLength(1));
      expect(controller.state.preset, TrafficMode.allVpn);
      expect(await stored(), TrafficMode.allVpn);
    });

    test('ignores another choice until the first one is saved', () async {
      final saving = controller.selectPreset(TrafficMode.allVpn, run);
      await controller.selectPreset(TrafficMode.smart, run);
      await saving;

      expect(controller.state.preset, TrafficMode.allVpn);
      expect(await stored(), TrafficMode.allVpn);
      expect(failures, isEmpty);
    });

    test('cannot connect while a choice is being saved', () async {
      await addSubscription();

      final saving = controller.selectPreset(TrafficMode.allVpn, run);
      expect(controller.state.canToggle, isFalse);
      await saving;

      expect(controller.state.canToggle, isTrue);
    });

    test('cannot change while a connection is in progress', () async {
      await addSubscription();
      unawaited(controller.toggle(run, explain: _explainNever));
      await settle();

      await controller.selectPreset(TrafficMode.allVpn, run);

      expect(controller.state.preset, TrafficMode.smart);
      expect(await stored(), TrafficMode.smart);
    });
  });
}

/// These connections already have VPN permission, so nothing is explained.
Future<bool> _explainNever() => fail('VPN permission is not asked here');
