import 'dart:async';

import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';

enum HomeStatus {
  off,
  connecting,
  reconnecting,
  connected,
  disconnecting,
  failed,

  /// A command failed and the tunnel may still be up.
  uncertain,
}

enum HomeRequest { connect, disconnect }

/// Runs a connection command and reports its failure to the user.
typedef ConnectionActionRunner = Future<void> Function(
  Future<void> Function() action,
);

class HomeState {
  HomeState({
    this.view = const ConnectionView(),
    ServerCatalog? catalog,
    this.request,
    this.restoring = false,
  }) : catalog = catalog ?? ServerCatalog();

  final ConnectionView view;
  final ServerCatalog catalog;

  // A command may wait for permission or the serial queue before it publishes
  // a phase. The tap is acknowledged at once without claiming a native state.
  final HomeRequest? request;

  /// The session fell from connected to connecting, so the system is restoring
  /// it. The same phase after off is a start from outside the app.
  final bool restoring;

  HomeStatus get status {
    if (request == HomeRequest.disconnect) return HomeStatus.disconnecting;
    if (request == HomeRequest.connect) return HomeStatus.connecting;
    return switch (view.phase) {
      ConnectionPhase.connected => HomeStatus.connected,
      ConnectionPhase.disconnecting => HomeStatus.disconnecting,
      ConnectionPhase.preparing => HomeStatus.connecting,
      ConnectionPhase.connecting =>
        restoring ? HomeStatus.reconnecting : HomeStatus.connecting,
      ConnectionPhase.disconnected || ConnectionPhase.failed =>
        view.canDisconnect
            ? HomeStatus.uncertain
            : _attemptFailed
            ? HomeStatus.failed
            : HomeStatus.off,
    };
  }

  /// Our own start publishes no runtime and can be cancelled. With a runtime no
  /// command is running here, so only a disconnect can stop it.
  bool get _cancellable =>
      request == HomeRequest.connect || view.runtime == null;

  bool get _attemptFailed =>
      view.failed &&
      !const {'cancelled', 'permissionRequired'}.contains(view.issue);

  /// The newest row, which is the one the latest deep link asked for even if
  /// removing the previous subscription has not finished.
  SubscriptionData? get subscription => catalog.sources.lastOrNull;

  bool get canToggle => switch (status) {
    HomeStatus.disconnecting => false,
    HomeStatus.off || HomeStatus.failed => subscription != null,
    _ => true,
  };

  String? get location {
    final runtime = view.runtime;
    final running =
        runtime?.profile?.name ?? runtime?.entries.firstOrNull?.name;
    if (running != null) return running;
    final first = catalog.servers.firstOrNull;
    return first == null ? null : catalog.display(first).name;
  }

  DateTime? get connectedSince => view.runtime?.startedAt;

  /// Null when the panel sets no expiry. A partial day counts as a whole one.
  int? daysLeft(DateTime now) {
    final row = subscription;
    final expiresAt = row == null
        ? null
        : SubscriptionUserInfo.fromSubscription(row)?.expiresAt;
    if (expiresAt == null) return null;
    final left = expiresAt.difference(now).inMilliseconds;
    return left <= 0 ? 0 : (left / Duration.millisecondsPerDay).ceil();
  }

  HomeState copyWith({
    ConnectionView? view,
    ServerCatalog? catalog,
    bool? restoring,
  }) => HomeState(
    view: view ?? this.view,
    catalog: catalog ?? this.catalog,
    request: request,
    restoring: restoring ?? this.restoring,
  );

  HomeState _withRequest(HomeRequest? request) => HomeState(
    view: view,
    catalog: catalog,
    request: request,
    restoring: restoring,
  );
}

class HomeController extends PageCubit<HomeState> {
  HomeController({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    Future<PlatformPermissionResult> Function()? requestPermission,
  }) : _db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       _requestPermission =
           requestPermission ?? AppHostApi().requestPlatformPermission,
       super(HomeState()) {
    this.coordinator.state.addListener(_connectionChanged);
    _connectionChanged();
  }

  final AppDatabase _db;
  final ConnectionCoordinator coordinator;
  final Future<PlatformPermissionResult> Function() _requestPermission;
  StreamSubscription<ServerCatalog>? _catalog;

  void _connectionChanged() {
    final view = coordinator.state.value;
    final wasUp =
        state.view.phase == ConnectionPhase.connected || state.restoring;
    emit(
      state.copyWith(
        view: view,
        restoring:
            wasUp &&
            view.phase == ConnectionPhase.connecting &&
            view.runtime != null,
      ),
    );
  }

  Future<void> initialize() async {
    _catalog ??= ServerCatalog.watch(_db).listen(
      (catalog) => emit(state.copyWith(catalog: catalog)),
      onError: (Object error) =>
          ygLogger('read home catalog failed (${error.runtimeType})'),
    );
  }

  /// Connects from off, cancels a connection in progress, otherwise disconnects.
  Future<void> toggle(ConnectionActionRunner run) async {
    if (!state.canToggle) return;
    switch (state.status) {
      case HomeStatus.connecting when state._cancellable:
        coordinator.cancel();
      case HomeStatus.off || HomeStatus.failed:
        await _perform(HomeRequest.connect, run, _connect);
      case HomeStatus.disconnecting:
        break;
      default:
        await _perform(HomeRequest.disconnect, run, coordinator.disconnect);
    }
  }

  Future<void> _connect() async {
    final view = state.view;
    if (view.issue == 'permissionRequired' && view.permission != null) {
      await _requestPermission();
    }
    await coordinator.connect();
  }

  Future<void> _perform(
    HomeRequest request,
    ConnectionActionRunner run,
    Future<void> Function() action,
  ) async {
    emit(state._withRequest(request));
    try {
      await run(action);
    } finally {
      emit(state._withRequest(null));
    }
  }

  @override
  Future<void> disposePageResources() async {
    coordinator.state.removeListener(_connectionChanged);
    await _catalog?.cancel();
  }
}
