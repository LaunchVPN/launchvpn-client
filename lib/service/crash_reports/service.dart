import 'package:flutter/foundation.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/crash_reports/scrub.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Where crash reports go: Sentry in the App, a stand-in in tests.
abstract interface class CrashReporter {
  Future<void> start();
  Future<void> stop();
  Future<void> capture(SentryEvent event);
}

/// «Отчёты о сбоях»: on by default, off by the switch in Settings. While off,
/// nothing is captured or sent.
final class CrashReports {
  CrashReports({required this._reporter});

  static final instance = CrashReports(reporter: const SentryCrashReporter());

  final CrashReporter _reporter;

  /// `main` calls this before the first frame, so a crash during startup is
  /// reported too.
  Future<void> start() async {
    try {
      if (await enabled) await _reporter.start();
    } catch (error) {
      ygLogger('start crash reports failed (${error.runtimeType})');
    }
  }

  Future<bool> get enabled => PreferencesKey().readCrashReports();

  /// Sends an event the App builds itself, such as how a tunnel run ended,
  /// unless reports are off. The scrubber still sees it.
  Future<void> report(SentryEvent event) async {
    try {
      if (await enabled) await _reporter.capture(event);
    } catch (error) {
      ygLogger('report event failed (${error.runtimeType})');
    }
  }

  /// A save that fails throws and changes nothing. Once saved, a reporter that
  /// fails to follow at once follows at the next launch.
  Future<void> setEnabled(bool value) async {
    await PreferencesKey().saveCrashReports(value);
    try {
      await (value ? _reporter.start() : _reporter.stop());
    } catch (error) {
      ygLogger('apply crash reports failed (${error.runtimeType})');
    }
  }

  /// Until [noticeShown], every launch is the first one, whose toast says
  /// what reports hold.
  Future<bool> get noticeDue async =>
      !await PreferencesKey().readCrashReportsNoticeShown();

  Future<void> noticeShown() => PreferencesKey().saveCrashReportsNoticeShown();
}

/// Catches Dart errors and the main process's native crashes. The tunnel runs
/// in another process (the Android `:native` one, the iOS extension), where
/// Sentry does not start.
final class SentryCrashReporter implements CrashReporter {
  const SentryCrashReporter();

  @override
  Future<void> start() async {
    // Debug runs stay out of the project; a release build on an emulator
    // reports.
    if (!kReleaseMode || Sentry.isEnabled) return;
    await SentryFlutter.init(_configure);
  }

  @override
  Future<void> stop() => Sentry.close();

  @override
  Future<void> capture(SentryEvent event) => Sentry.captureEvent(event);

  static void _configure(SentryFlutterOptions options) {
    options
      ..dsn = Brand.sentryDsn
      ..sendDefaultPii = false
      ..enableAutoSessionTracking = false
      // ygLogger prints errors that may hold links; the scrubber would catch
      // them, but they say little a stack trace does not.
      ..enablePrintBreadcrumbs = false
      ..enableAutoNativeBreadcrumbs = false
      ..enableUserInteractionBreadcrumbs = false
      // iOS would record request URLs natively, out of the scrubber's reach.
      ..recordHttpBreadcrumbs = false
      ..beforeSend = ((event, _) => scrubEvent(event))
      ..beforeBreadcrumb = ((breadcrumb, _) =>
          breadcrumb == null ? null : scrubBreadcrumb(breadcrumb));
  }
}
