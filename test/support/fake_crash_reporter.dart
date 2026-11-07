import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/crash_reports/service.dart';

/// Stands in for Sentry and tells whether reports would be sent.
final class FakeCrashReporter implements CrashReporter {
  bool sending = false;
  final tunnelStops = <TunnelStop>[];

  @override
  Future<void> start() async => sending = true;

  @override
  Future<void> stop() async => sending = false;

  @override
  Future<void> reportTunnelStop(TunnelStop stop) async => tunnelStops.add(stop);
}
