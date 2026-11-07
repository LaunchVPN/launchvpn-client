import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/crash_reports/server_silence_event.dart';
import 'package:onexray/service/crash_reports/service.dart';
import 'package:onexray/service/servers/locations.dart';
import 'package:onexray/service/shared/app_lifecycle.dart';
import 'package:onexray/service/shared/ping/state.dart';

/// Opens an address through the tunnel. Returns how long the answer took in
/// milliseconds, or null when none came.
typedef ProbeTunnel = Future<int?> Function();

/// What the check knows about the running session.
@immutable
class ConnectionCheckView {
  const ConnectionCheckView({
    this.session,
    this.passed = false,
    this.recovering = false,
    this.delayMs,
  });

  /// The `ConnectionRuntime.identity` the rest describes.
  final String? session;

  /// A check got through this session. It stays so until checks fail.
  final bool passed;

  /// The App restarted the session after its server went silent and no
  /// check has got through since.
  final bool recovering;

  /// How long the last check that got through took.
  final int? delayMs;

  /// Whether [runtime] got through a check. Without one it may only be up.
  bool reached(ConnectionRuntime runtime) =>
      passed && session == runtime.identity;
}

/// Tells whether the running VPN reaches the internet. «Подключено» only says
/// the tunnel is up; Xray switches from a dead server of the group on its own,
/// but only after the panel's next round of checks, minutes later.
///
/// While the App is visible, it opens the address «Локации» measures, through
/// the tunnel: at once, back in the App, when the network changes and every
/// [interval]. Two failures in a row restart the session once, which measures
/// every server of the group and leads with a live one. If the session stays
/// silent, the VPN goes off with the failure Home already shows for a group
/// that did not answer. Sentry gets one event per episode either way.
final class ConnectionCheck with WidgetsBindingObserver {
  ConnectionCheck({
    required this._connection,
    required this._restart,
    required this._stop,
    required this._probe,
    required this._network,
    required this._networkChanges,
    required this._report,
  });

  /// Null where the App's own traffic does not take the tunnel.
  static final ConnectionCheck? instance = offeredOn(connectionPlatform)
      ? ConnectionCheck(
          connection: ConnectionCoordinator.instance.state,
          restart: ConnectionCoordinator.instance.restartSilent,
          stop: ConnectionCoordinator.instance.stopSilent,
          probe: probeTunnel,
          network: readNetwork,
          networkChanges: Connectivity().onConnectivityChanged,
          report: (silence) =>
              CrashReports.instance.report(serverSilenceEvent(silence)),
        )
      : null;

  static bool offeredOn(ConnectionPlatform platform) =>
      platform == ConnectionPlatform.android ||
      platform == ConnectionPlatform.ios;

  static const interval = Duration(seconds: 30);

  /// The pause before the check that decides, so that a balancer that just
  /// lost a server has a moment to move on.
  static const retry = Duration(seconds: 3);

  /// Failures in a row before the App acts, before and after the switch.
  static const failuresToAct = 2;

  final ValueListenable<ConnectionView> _connection;

  /// `ConnectionCoordinator.restartSilent`.
  final Future<void> Function() _restart;

  /// `ConnectionCoordinator.stopSilent`.
  final Future<void> Function() _stop;
  final ProbeTunnel _probe;
  final Future<NetworkKind> Function() _network;
  final Stream<Object?> _networkChanges;
  final Future<void> Function(ServerSilence) _report;

  final view = ValueNotifier(const ConnectionCheckView());
  StreamSubscription<Object?>? _networkSubscription;
  Timer? _next;
  bool _visible = true;
  bool _probing = false;
  bool _restarting = false;
  int _failures = 0;
  _Episode? _episode;

  /// `main` calls it once the coordinator is set up.
  void start() {
    if (_networkSubscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    _visible = isAppVisible(WidgetsBinding.instance.lifecycleState);
    _networkSubscription = _networkChanges.listen((_) => checkNow());
    _connection.addListener(_sessionChanged);
    _sessionChanged();
  }

  ConnectionRuntime? get _running {
    final current = _connection.value;
    return current.phase == ConnectionPhase.connected ? current.runtime : null;
  }

  /// Traffic samples notify every second, so only a new session counts.
  void _sessionChanged() {
    final runtime = _running;
    if (runtime == null) {
      _next?.cancel();
      // The restart passes through these phases; the check resumes after it.
      if (!_restarting) _forget();
      return;
    }
    if (view.value.session == runtime.identity) return;
    view.value = ConnectionCheckView(
      session: runtime.identity,
      recovering: _episode?.switched ?? false,
    );
    checkNow();
  }

  void _forget() {
    _failures = 0;
    _episode = null;
    if (view.value.session != null) view.value = const ConnectionCheckView();
  }

  /// Checks at once, unless a check is already under way.
  void checkNow() {
    _next?.cancel();
    final runtime = _running;
    if (runtime == null || !_visible || _probing || _restarting) return;
    unawaited(_check(runtime));
  }

  void _schedule(Duration after) {
    _next?.cancel();
    _next = Timer(after, checkNow);
  }

  Future<void> _check(ConnectionRuntime runtime) async {
    _probing = true;
    final NetworkKind network;
    final int? delay;
    try {
      network = await _network();
      // Without a network there is nothing to reach; its return checks again.
      delay = network == NetworkKind.none ? null : await _probe();
    } finally {
      _probing = false;
    }
    if (_running?.identity != runtime.identity) return;
    if (network == NetworkKind.none) return;
    if (delay != null) {
      _passed(runtime, delay, network);
    } else {
      _failed(runtime, network);
    }
  }

  void _passed(ConnectionRuntime runtime, int delay, NetworkKind network) {
    final episode = _episode;
    if (episode != null && episode.switched) {
      unawaited(_send(episode, network, recovered: true));
    }
    _failures = 0;
    _episode = null;
    view.value = ConnectionCheckView(
      session: runtime.identity,
      passed: true,
      delayMs: delay,
    );
    _schedule(interval);
  }

  void _failed(ConnectionRuntime runtime, NetworkKind network) {
    _failures++;
    final episode = _episode ??= _Episode(
      since: runtime.startedAt,
      location: runtime.profile?.name,
    );
    if (_failures < episode.actAt) {
      _schedule(retry);
    } else if (!episode.switched) {
      episode
        ..switched = true
        ..actAt += failuresToAct;
      view.value = ConnectionCheckView(
        session: runtime.identity,
        recovering: true,
      );
      unawaited(_switchServers(episode, network));
    } else {
      unawaited(_giveUp(episode, network));
    }
  }

  Future<void> _switchServers(_Episode episode, NetworkKind network) async {
    _restarting = true;
    try {
      await _restart();
    } catch (error) {
      // A cancel or any other failure is not about the servers.
      if (connectionFailureReason(error) ==
          ConnectionResolutionFailure.insufficientHealthyServers.name) {
        await _send(episode, network, recovered: false);
      }
    } finally {
      _restarting = false;
      // The new session came up while the restart ran, unchecked.
      _sessionChanged();
      checkNow();
    }
  }

  Future<void> _giveUp(_Episode episode, NetworkKind network) async {
    await _send(episode, network, recovered: false);
    try {
      await _stop();
    } catch (error) {
      ygLogger('stop silent session failed (${error.runtimeType})');
    }
  }

  Future<void> _send(
    _Episode episode,
    NetworkKind network, {
    required bool recovered,
  }) => _report(
    ServerSilence(
      location: switch (episode.location) {
        final label? => Location.parse(id: 0, label: label, delay: 0).name,
        null => null,
      },
      ran: DateTime.now().difference(episode.since),
      network: network,
      failedChecks: _failures,
      switched: episode.switched,
      recovered: recovered,
    ),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasVisible = _visible;
    _visible = isAppVisible(state);
    if (!_visible) {
      _next?.cancel();
    } else if (!wasVisible) {
      checkNow();
    }
  }

  void dispose() {
    _next?.cancel();
    unawaited(_networkSubscription?.cancel());
    _networkSubscription = null;
    _connection.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// Checks in a row that failed, from the first failure to the next success.
class _Episode {
  _Episode({required this.since, required this.location});

  /// When the session that went silent started.
  final DateTime since;
  final String? location;
  bool switched = false;
  int actAt = ConnectionCheck.failuresToAct;
}

/// The App's own traffic takes the tunnel on Android and iOS, so a request
/// from here goes the way the person's apps do, through routing and the
/// group's balancer. Any HTTP answer means the server got it through.
Future<int?> probeTunnel() async {
  const timeout = Duration(seconds: 4);
  final ping = PingState();
  await ping.readFromPreferences();
  final client = HttpClient()..connectionTimeout = timeout;
  final watch = Stopwatch()..start();
  try {
    return await () async {
      final request = await client.getUrl(Uri.parse(ping.realUrl));
      request.followRedirects = false;
      final response = await request.close();
      await response.drain<void>();
      return watch.elapsedMilliseconds;
    }().timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Wi-Fi first, as a phone on Wi-Fi with mobile data on uses it.
Future<NetworkKind> readNetwork() async {
  try {
    final kinds = await Connectivity().checkConnectivity();
    if (kinds.contains(ConnectivityResult.wifi)) return NetworkKind.wifi;
    if (kinds.contains(ConnectivityResult.mobile)) return NetworkKind.cellular;
    if (kinds.every((kind) => kind == ConnectivityResult.none)) {
      return NetworkKind.none;
    }
    return NetworkKind.other;
  } catch (_) {
    return NetworkKind.other;
  }
}
