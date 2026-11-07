import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/tunnel_probe.dart';
import 'package:onexray/service/crash_reports/server_silence_event.dart';
import 'package:onexray/service/crash_reports/service.dart';
import 'package:onexray/service/servers/locations.dart';
import 'package:onexray/service/shared/app_lifecycle.dart';

/// Where the check stands with a session.
enum ConnectionCheckStage {
  /// The tunnel is up and no check has got through it yet.
  checking,

  /// The App restarted the session after its server went silent, and no
  /// check has got through the new one yet.
  switching,

  /// A check got through. It stays so until checks fail.
  reached,
}

/// What the check knows about the running session.
@immutable
class ConnectionCheckView {
  const ConnectionCheckView({
    this.session,
    this.stage = ConnectionCheckStage.checking,
    this.delayMs,
  });

  /// The `ConnectionRuntime.identity` the rest describes.
  final String? session;
  final ConnectionCheckStage stage;

  /// How long the last check that got through took.
  final int? delayMs;

  /// Whether [runtime] got through a check. Without one it may only be up.
  bool reached(ConnectionRuntime runtime) =>
      stage == ConnectionCheckStage.reached && session == runtime.identity;
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

  /// The check restarts or stops the session; it waits for that to end.
  bool _acting = false;
  _Episode? _episode;

  /// `main` calls it once the coordinator is set up.
  void start() {
    if (_networkSubscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    _visible = isAppVisible(WidgetsBinding.instance.lifecycleState);
    _networkSubscription = _networkChanges.listen((_) => _networkChanged());
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
      // A restart passes through these phases; the check resumes after it.
      if (!_acting) _forget();
      return;
    }
    if (view.value.session == runtime.identity) return;
    view.value = ConnectionCheckView(
      session: runtime.identity,
      stage: (_episode?.switched ?? false)
          ? ConnectionCheckStage.switching
          : ConnectionCheckStage.checking,
    );
    checkNow();
  }

  void _forget() {
    _episode = null;
    if (view.value.session != null) view.value = const ConnectionCheckView();
  }

  /// Failures before a pause or on another network say nothing about now, so
  /// the count starts over, keeping only the switch already made.
  void _startOver() {
    final episode = _episode;
    if (episode == null || !episode.switched) {
      _episode = null;
    } else {
      episode.inRow = 0;
    }
  }

  /// A handover drops connections for a moment, so the check waits as long
  /// as for a retry instead of failing on it.
  void _networkChanged() {
    if (_acting) return;
    _startOver();
    _schedule(retry);
  }

  /// Checks at once, unless a check is already under way.
  void checkNow() {
    _next?.cancel();
    final runtime = _running;
    if (runtime == null || !_visible || _probing || _acting) return;
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
    if (_running?.identity != runtime.identity) {
      // A new session came up meanwhile and found this check under way.
      checkNow();
    } else if (network == NetworkKind.none) {
      // Its return is a network change too; this catches a missed one.
      _schedule(interval);
    } else if (delay != null) {
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
    _episode = null;
    view.value = ConnectionCheckView(
      session: runtime.identity,
      stage: ConnectionCheckStage.reached,
      delayMs: delay,
    );
    _schedule(interval);
  }

  void _failed(ConnectionRuntime runtime, NetworkKind network) {
    final episode = _episode ??= _Episode(
      since: runtime.startedAt,
      location: runtime.profile?.name,
    );
    episode.fail();
    if (episode.inRow < failuresToAct) {
      _schedule(retry);
    } else if (!episode.switched) {
      episode
        ..switched = true
        ..inRow = 0;
      view.value = ConnectionCheckView(
        session: runtime.identity,
        stage: ConnectionCheckStage.switching,
      );
      unawaited(
        _act(
          _restart,
          failed: () => unawaited(_send(episode, network, recovered: false)),
        ),
      );
    } else {
      unawaited(_send(episode, network, recovered: false));
      unawaited(_act(_stop));
    }
  }

  /// Restarts or stops the session, and checks wait for it. A restart that
  /// fails for any reason but a cancel leaves the person offline, which
  /// [failed] reports.
  Future<void> _act(
    Future<void> Function() action, {
    void Function()? failed,
  }) async {
    _acting = true;
    _next?.cancel();
    try {
      await action();
    } catch (error) {
      if (connectionFailureReason(error) != 'cancelled') failed?.call();
      ygLogger('act on silent session failed (${error.runtimeType})');
    } finally {
      _acting = false;
      // A new session came up while the restart ran, unchecked.
      _sessionChanged();
      checkNow();
    }
  }

  Future<void> _send(
    _Episode episode,
    NetworkKind network, {
    required bool recovered,
  }) => _report(
    ServerSilence(
      location: switch (episode.location) {
        final label? => Location.nameOf(label),
        null => null,
      },
      ran: DateTime.now().difference(episode.since),
      network: network,
      failedChecks: episode.failed,
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
      if (!_acting) _startOver();
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

/// Checks that failed, from the first failure to the next success.
class _Episode {
  _Episode({required this.since, required this.location});

  /// When the session that went silent started.
  final DateTime since;
  final String? location;

  /// The App restarted the session to switch servers.
  bool switched = false;

  /// Failures in a row in the current session, which decide the next step.
  int inRow = 0;

  /// Every failure of the episode, for the report.
  int failed = 0;

  void fail() {
    inRow++;
    failed++;
  }
}
