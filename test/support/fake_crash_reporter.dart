import 'package:onexray/service/crash_reports/service.dart';

/// Stands in for Sentry and tells whether reports would be sent.
final class FakeCrashReporter implements CrashReporter {
  bool sending = false;

  @override
  Future<void> start() async => sending = true;

  @override
  Future<void> stop() async => sending = false;
}
