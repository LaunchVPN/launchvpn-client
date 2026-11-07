import 'dart:async';
import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/connection_check.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/crash_reports/server_silence_event.dart';

var _sessions = 0;

/// A new session of the «🇩🇪 Германия» group.
ConnectionRuntime _session() {
  _sessions++;
  final invoke = LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest('{}').toJson(),
  );
  return ConnectionRuntime.create(
    configuration: ConnectionConfiguration(),
    compiled: CompiledConnection(
      xrayJson: '{}',
      entries: const [],
      finalExit: null,
      nodeTags: const {},
      profile: ResolvedProfile(
        id: 1,
        sourceId: 1,
        name: '🇩🇪 Германия',
        config: const {},
      ),
    ),
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(
      null,
      null,
      '${18000 + _sessions}',
      jsonEncode(invoke.toJson()),
    ),
  );
}

ConnectionView _up(ConnectionRuntime runtime) =>
    ConnectionView(phase: ConnectionPhase.connected, runtime: runtime);

class _Harness {
  _Harness() {
    check = ConnectionCheck(
      connection: connection,
      restart: () async {
        restarts++;
        connection.value = const ConnectionView(
          phase: ConnectionPhase.disconnecting,
        );
        final failure = restartFailure;
        if (failure != null) {
          connection.value = const ConnectionView(
            phase: ConnectionPhase.failed,
          );
          throw failure;
        }
        connection.value = _up(_session());
      },
      stop: () async {
        stops++;
        connection.value = const ConnectionView(phase: ConnectionPhase.failed);
      },
      probe: () async {
        probes++;
        return answers.isEmpty ? null : answers.removeAt(0);
      },
      network: () async => network,
      networkChanges: networkChanges.stream,
      report: (silence) async => reports.add(silence),
    );
  }

  final connection = ValueNotifier(const ConnectionView());
  final networkChanges = StreamController<Object?>.broadcast();
  late final ConnectionCheck check;

  /// Delays the next probes return, a null for a probe that got no answer.
  final answers = <int?>[];
  var network = NetworkKind.wifi;
  Object? restartFailure;
  var probes = 0;
  var restarts = 0;
  var stops = 0;
  final reports = <ServerSilence>[];

  ConnectionCheckView get view => check.view.value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void run(void Function(FakeAsync time, _Harness harness) body) {
    fakeAsync((time) {
      final harness = _Harness();
      harness.check.start();
      body(time, harness);
      harness.check.dispose();
    });
  }

  test('a new session is unchecked until a check gets through', () {
    run((time, harness) {
      final session = _session();
      harness.answers.add(48);
      harness.connection.value = _up(session);

      expect(harness.view.reached(session), isFalse);
      time.flushMicrotasks();

      expect(harness.view.reached(session), isTrue);
      expect(harness.view.delayMs, 48);
    });
  });

  test('a session that got through is checked again every 30 seconds', () {
    run((time, harness) {
      harness.answers.addAll([48, 52]);
      harness.connection.value = _up(_session());
      time.flushMicrotasks();

      time.elapse(ConnectionCheck.interval);

      expect(harness.probes, 2);
      expect(harness.view.delayMs, 52);
    });
  });

  test('one failure keeps the session and tries again shortly', () {
    run((time, harness) {
      final session = _session();
      harness.answers.addAll([48, null, 60]);
      harness.connection.value = _up(session);
      time.flushMicrotasks();
      time.elapse(ConnectionCheck.interval);

      expect(harness.view.reached(session), isTrue);
      time.elapse(ConnectionCheck.retry);

      expect(harness.probes, 3);
      expect(harness.restarts, 0);
      expect(harness.view.delayMs, 60);
      expect(harness.reports, isEmpty);
    });
  });

  test('two failures switch servers once, and a recovery is reported', () {
    run((time, harness) {
      harness.answers.addAll([null, null, 75]);
      harness.connection.value = _up(_session());
      time.flushMicrotasks();
      time.elapse(ConnectionCheck.retry);

      expect(harness.restarts, 1);
      expect(harness.view.passed, isTrue);
      expect(harness.view.recovering, isFalse);
      expect(harness.view.delayMs, 75);
      final report = harness.reports.single;
      expect(report.recovered, isTrue);
      expect(report.switched, isTrue);
      expect(report.failedChecks, 2);
      expect(report.location, 'Германия');
      expect(report.network, NetworkKind.wifi);
    });
  });

  test('a new session stays recovering until a check gets through', () {
    run((time, harness) {
      harness.answers.addAll([null, null]);
      harness.connection.value = _up(_session());
      time.flushMicrotasks();
      // The new session's first check gets no answer either.
      time.elapse(ConnectionCheck.retry);

      expect(harness.restarts, 1);
      expect(harness.view.recovering, isTrue);
      expect(harness.view.passed, isFalse);
    });
  });

  test('silence after the switch turns the VPN off and is reported', () {
    run((time, harness) {
      harness.connection.value = _up(_session());
      time.flushMicrotasks();
      time.elapse(ConnectionCheck.retry);
      time.elapse(ConnectionCheck.retry);

      expect(harness.restarts, 1);
      expect(harness.stops, 1);
      expect(harness.probes, 4);
      final report = harness.reports.single;
      expect(report.recovered, isFalse);
      expect(report.failedChecks, 4);
      expect(harness.view.session, isNull);
    });
  });

  test('a group where no server answered is reported as lost', () {
    run((time, harness) {
      harness.restartFailure = const ConnectionResolutionException(
        ConnectionResolutionFailure.insufficientHealthyServers,
      );
      harness.connection.value = _up(_session());
      time.flushMicrotasks();
      time.elapse(ConnectionCheck.retry);

      expect(harness.stops, 0);
      expect(harness.reports.single.recovered, isFalse);
      expect(harness.view.session, isNull);
    });
  });

  test('a switch the person cancelled is not reported', () {
    run((time, harness) {
      harness.restartFailure = const ConnectionHostException('cancelled');
      harness.connection.value = _up(_session());
      time.flushMicrotasks();
      time.elapse(ConnectionCheck.retry);

      expect(harness.restarts, 1);
      expect(harness.reports, isEmpty);
    });
  });

  test('without a network nothing is checked until it returns', () {
    run((time, harness) {
      final session = _session();
      harness.network = NetworkKind.none;
      harness.connection.value = _up(session);
      time.elapse(const Duration(minutes: 1));

      expect(harness.probes, 0);
      expect(harness.view.reached(session), isFalse);

      harness
        ..network = NetworkKind.cellular
        ..answers.add(90);
      harness.networkChanges.add(null);
      time.flushMicrotasks();

      expect(harness.view.reached(session), isTrue);
    });
  });

  test('a hidden App checks nothing, and checks at once on return', () {
    run((time, harness) {
      harness.answers.addAll([48, 50]);
      harness.connection.value = _up(_session());
      time.flushMicrotasks();

      harness.check.didChangeAppLifecycleState(AppLifecycleState.paused);
      time.elapse(const Duration(minutes: 5));
      expect(harness.probes, 1);

      harness.check.didChangeAppLifecycleState(AppLifecycleState.resumed);
      time.flushMicrotasks();
      expect(harness.probes, 2);
      expect(harness.view.delayMs, 50);
    });
  });

  test('turning the VPN off forgets the session', () {
    run((time, harness) {
      harness.answers.add(48);
      harness.connection.value = _up(_session());
      time.flushMicrotasks();

      harness.connection.value = const ConnectionView();

      expect(harness.view.session, isNull);
      time.elapse(ConnectionCheck.interval);
      expect(harness.probes, 1);
    });
  });
}
