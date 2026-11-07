import 'package:onexray/service/crash_reports/service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Stands in for Sentry and tells whether reports would be sent.
final class FakeCrashReporter implements CrashReporter {
  bool sending = false;
  final events = <SentryEvent>[];

  @override
  Future<void> start() async => sending = true;

  @override
  Future<void> stop() async => sending = false;

  @override
  Future<void> capture(SentryEvent event) async => events.add(event);
}
