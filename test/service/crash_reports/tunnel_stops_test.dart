import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/crash_reports/service.dart';
import 'package:onexray/service/crash_reports/tunnel_stop_event.dart';
import 'package:onexray/service/crash_reports/tunnel_stops.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_crash_reporter.dart';

final _start = DateTime.utc(2026, 11, 6, 9, 30);

TunnelStop _stop(String? reason, {Duration ran = const Duration(hours: 2)}) =>
    TunnelStop(
      reason: reason,
      startedAtMs: _start.millisecondsSinceEpoch,
      endedAtMs: _start.add(ran).millisecondsSinceEpoch,
      startedByApp: true,
      memory: TunnelMemory(
        footprint: 31 * 1048576,
        peak: 34 * 1048576,
        limit: 50 * 1048576,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TunnelStopReports', () {
    late List<List<TunnelStop>> pending;
    late List<TunnelStop> reported;
    late StreamController<VpnStatus> statuses;
    late int takes;
    late TunnelStopReports reports;

    setUp(() {
      pending = [];
      reported = [];
      takes = 0;
      statuses = StreamController<VpnStatus>.broadcast(sync: true);
      reports = TunnelStopReports(
        take: () async {
          takes++;
          return pending.isEmpty ? const [] : pending.removeAt(0);
        },
        report: (stop) async => reported.add(stop),
        statuses: statuses.stream,
      );
    });

    tearDown(() async {
      reports.dispose();
      await statuses.close();
    });

    test('a stop iOS made is reported, one from the button is not', () async {
      pending.add([
        _stop('userInitiated'),
        _stop('noNetworkAvailable'),
        _stop(null),
      ]);

      await reports.send();

      expect(reported.map((stop) => stop.reason), ['noNetworkAvailable', null]);
    });

    test('the VPN going off asks for the stops again', () async {
      reports.start();
      await pumpEventQueue();
      expect(takes, 1);
      pending.add([_stop('unrecoverableNetworkChange')]);

      statuses
        ..add(VpnStatus.connected)
        ..add(VpnStatus.disconnected)
        ..add(VpnStatus.disconnected);
      await pumpEventQueue();

      expect(takes, 2);
      expect(reported.single.reason, 'unrecoverableNetworkChange');
    });

    test('a record the App cannot read sends nothing', () async {
      final failing = TunnelStopReports(
        take: () async => throw PlatformException(code: 'channel-error'),
        report: (stop) async => reported.add(stop),
        statuses: const Stream.empty(),
      );

      await failing.send();

      expect(reported, isEmpty);
    });
  });

  group('tunnelStopEvent', () {
    test(
      'names why iOS stopped the tunnel, how long it ran and its memory',
      () {
        final event = tunnelStopEvent(
          _stop('noNetworkAvailable', ran: const Duration(minutes: 95)),
        );

        expect(
          event.message?.formatted,
          'iOS stopped the VPN: noNetworkAvailable',
        );
        expect(event.level, SentryLevel.warning);
        expect(event.timestamp, _start.add(const Duration(minutes: 95)));
        expect(event.fingerprint, ['tunnel-stop', 'noNetworkAvailable']);
        expect(event.tags, {
          'tunnel.stop_reason': 'noNetworkAvailable',
          'tunnel.started_by': 'app',
        });
        expect(event.contexts['tunnel'], {
          'ran_minutes': 95,
          'footprint_mb': 31,
          'peak_mb': 34,
          'limit_mb': 50,
        });
      },
    );

    test('a run that ended without a stop says the process died', () {
      final stop = _stop(null)..startedByApp = false;

      final event = tunnelStopEvent(stop);

      expect(
        event.message?.formatted,
        'The VPN process ended without a stop: a crash or the memory limit',
      );
      expect(event.fingerprint, ['tunnel-stop', 'no-stop']);
      expect(event.tags?['tunnel.stop_reason'], 'none');
      expect(event.tags?['tunnel.started_by'], 'on-demand');
    });
  });

  test('with crash reports off, a tunnel stop is not sent', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final reporter = FakeCrashReporter();
    final crashReports = CrashReports(reporter: reporter);

    await crashReports.setEnabled(false);
    await crashReports.reportTunnelStop(_stop('noNetworkAvailable'));
    await crashReports.setEnabled(true);
    await crashReports.reportTunnelStop(_stop('sleep'));

    expect(reporter.tunnelStops.map((stop) => stop.reason), ['sleep']);
  });
}
