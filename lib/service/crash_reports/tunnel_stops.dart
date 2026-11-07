import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/crash_reports/service.dart';
import 'package:onexray/service/crash_reports/tunnel_stop_event.dart';

/// Reports the iOS tunnel's runs that iOS ended, so a VPN that went off on
/// its own leaves a reason in Sentry. A stop by the user, from the App, the
/// Widget or iOS Settings, is not reported. The extension keeps its runs
/// until the App asks: at launch, back in the App and when the VPN goes off.
final class TunnelStopReports with WidgetsBindingObserver {
  TunnelStopReports({
    required this._take,
    required this._report,
    required this._statuses,
  });

  static final instance = TunnelStopReports(
    take: TunnelStopsHostApi().takeTunnelStops,
    report: (stop) => CrashReports.instance.report(tunnelStopEvent(stop)),
    statuses: AppFlutterApi().vpnStatusController.stream,
  );

  static const _byUser = 'userInitiated';

  final Future<List<TunnelStop>> Function() _take;
  final Future<void> Function(TunnelStop) _report;
  final Stream<VpnStatus> _statuses;
  StreamSubscription<VpnStatus>? _subscription;

  /// iOS only; `main` calls it once the bridge is set up.
  void start() {
    if (_subscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    _subscription = _statuses
        .distinct()
        .where((status) => status == VpnStatus.disconnected)
        .listen((_) => unawaited(send()));
    unawaited(send());
  }

  /// Each run comes from the extension once, so calls may overlap.
  Future<void> send() async {
    final List<TunnelStop> stops;
    try {
      stops = await _take();
    } catch (error) {
      ygLogger('take tunnel stops failed (${error.runtimeType})');
      return;
    }
    for (final stop in stops) {
      if (stop.reason != _byUser) await _report(stop);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(send());
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}
