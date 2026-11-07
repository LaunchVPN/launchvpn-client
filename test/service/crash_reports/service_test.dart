import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/crash_reports/service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_crash_reporter.dart';

void main() {
  test('with crash reports off, an event is not sent', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final reporter = FakeCrashReporter();
    final crashReports = CrashReports(reporter: reporter);

    await crashReports.setEnabled(false);
    await crashReports.report(SentryEvent(message: SentryMessage('off')));
    await crashReports.setEnabled(true);
    await crashReports.report(SentryEvent(message: SentryMessage('on')));

    expect(reporter.events.map((event) => event.message?.formatted), ['on']);
  });
}
