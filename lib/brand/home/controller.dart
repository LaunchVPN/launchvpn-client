import 'dart:async';

import 'package:collection/collection.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/locations.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';
import 'package:onexray/service/shared/ping/service.dart';

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

enum HomeRequest { connect, disconnect, reconnect, saveChoice }

/// Runs a connection command and reports its failure to the user.
typedef ConnectionActionRunner = Future<void> Function(
  Future<void> Function() action,
);

typedef LocationPing = Future<void> Function(
  List<CoreConfigData> rows, {
  bool Function()? isCancelled,
});

typedef AnnouncementDismissal = Future<void> Function(int subId, String text);

class HomeState {
  HomeState({
    this.view = const ConnectionView(),
    ServerCatalog? catalog,
    this.request,
    this.restoring = false,
    this.preset,
    this.selection,
  }) : catalog = catalog ?? ServerCatalog();

  final ConnectionView view;
  final ServerCatalog catalog;

  /// Null until the saved preset is read.
  final TrafficMode? preset;
  final ServerSelection? selection;

  // A command may wait for permission or the serial queue before it publishes
  // a phase. The tap is acknowledged at once without claiming a native state.
  final HomeRequest? request;

  /// The session fell from connected to connecting, so the system is restoring
  /// it. The same phase after off is a start from outside the app.
  final bool restoring;

  HomeStatus get status {
    if (request == HomeRequest.disconnect) return HomeStatus.disconnecting;
    if (request == HomeRequest.connect) return HomeStatus.connecting;
    if (request == HomeRequest.reconnect) return HomeStatus.reconnecting;
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

  /// Without a subscription there was nothing to connect to, which is what the
  /// screen says instead.
  bool get _attemptFailed =>
      subscription != null &&
      view.failed &&
      !const {'cancelled', 'permissionRequired'}.contains(view.issue);

  /// The newest row, which is the one the latest deep link asked for even if
  /// removing the previous subscription has not finished.
  SubscriptionData? get subscription => catalog.sources.lastOrNull;

  /// What the panel announced, unless the user closed this text.
  String? get announcement {
    final row = subscription;
    return row?.announce == row?.dismissedAnnounce ? null : row?.announce;
  }

  bool get canToggle => switch (status) {
    _ when request == HomeRequest.saveChoice => false,
    HomeStatus.disconnecting => false,
    HomeStatus.off || HomeStatus.failed => subscription != null,
    _ => true,
  };

  /// A choice made mid-transition would race the command already running.
  bool get canChangeConnection =>
      preset != null &&
      request == null &&
      const {
        HomeStatus.off,
        HomeStatus.failed,
        HomeStatus.connected,
      }.contains(status);

  /// A measurement taken through a running tunnel would describe the tunnel.
  bool get canMeasure =>
      request == null &&
      const {HomeStatus.off, HomeStatus.failed}.contains(status);

  late final LocationList locations = LocationList.from(catalog);

  /// The location the next connection uses. A connection that was starting
  /// during a refresh can leave the selection on a row the list has replaced.
  Location? get selectedLocation {
    final current = selection;
    if (current?.kind != SelectionKind.server) return locations.first;
    final row = catalog.servers.firstWhereOrNull(
      (row) => row.id == current!.id,
    );
    return (row == null ? null : locations.named(catalog.display(row).name)) ??
        locations.first;
  }

  /// The location to show: the running one, unless a choice is replacing it.
  Location? get location {
    final runtime = view.runtime;
    final running =
        runtime?.profile?.name ?? runtime?.entries.firstOrNull?.name;
    if (running == null || request == HomeRequest.reconnect) {
      return selectedLocation;
    }
    // A refresh may have replaced the running row, or the panel dropped it.
    return locations.named(running) ??
        Location.parse(
          id: runtime!.profile?.id ?? runtime.entries.first.id,
          label: running,
          delay: PingDelayConstants.unknown,
        );
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
    TrafficMode? preset,
    ServerSelection? selection,
  }) => HomeState(
    view: view ?? this.view,
    catalog: catalog ?? this.catalog,
    request: request,
    restoring: restoring ?? this.restoring,
    preset: preset ?? this.preset,
    selection: selection ?? this.selection,
  );

  HomeState _withRequest(HomeRequest? request) => HomeState(
    view: view,
    catalog: catalog,
    request: request,
    restoring: restoring,
    preset: preset,
    selection: selection,
  );
}

class HomeController extends PageCubit<HomeState> {
  HomeController({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    Future<PlatformPermissionResult> Function()? requestPermission,
    LocationPing? pingLocations,
    AnnouncementDismissal? dismissAnnounce,
  }) : _db = database ?? AppDatabase(),
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       _requestPermission =
           requestPermission ?? AppHostApi().requestPlatformPermission,
       _pingLocations = pingLocations ?? PingService().pingLocations,
       _dismissAnnounce =
           dismissAnnounce ?? SubscriptionService().dismissAnnounce,
       super(HomeState()) {
    this.coordinator.state.addListener(_connectionChanged);
    _connectionChanged();
  }

  final AppDatabase _db;
  final ConnectionCoordinator coordinator;
  final Future<PlatformPermissionResult> Function() _requestPermission;
  final LocationPing _pingLocations;
  final AnnouncementDismissal _dismissAnnounce;
  StreamSubscription<ServerCatalog>? _catalog;
  StreamSubscription<void>? _settings;
  bool _measuring = false;

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
    // A subscription refresh moves the stored selection.
    _settings ??= coordinator.configurationChanges.listen(
      (_) => unawaited(_showStoredChoices()),
      onError: (Object error) =>
          ygLogger('watch home settings failed (${error.runtimeType})'),
    );
    await _showStoredChoices();
  }

  Future<void> _showStoredChoices() async {
    try {
      final stored = await coordinator.configuration;
      if (isClosed) return;
      emit(
        state.copyWith(
          preset: stored.connection.trafficMode,
          selection: stored.connection.selection,
        ),
      );
    } catch (error) {
      ygLogger('read home settings failed (${error.runtimeType})');
    }
  }

  /// Saves the preset. A running tunnel reconnects at once, because a preset
  /// that only applies later would show a mode that is not in effect.
  Future<void> selectPreset(
    TrafficMode preset,
    ConnectionActionRunner run,
  ) async {
    if (!state.canChangeConnection || preset == state.preset) return;
    final request = _choiceRequest;
    emit(state.copyWith(preset: preset));
    await _perform(request, run, () => coordinator.applyTrafficMode(preset));
    await _showStoredChoices();
  }

  /// Saves the location, with the same immediate reconnect as a preset.
  Future<void> selectLocation(
    Location location,
    ConnectionActionRunner run,
  ) async {
    if (!state.canChangeConnection ||
        location.id == state.selectedLocation?.id) {
      return;
    }
    final request = _choiceRequest;
    final selection = ServerSelection.server(location.id);
    emit(state.copyWith(selection: selection));
    await _perform(request, run, () => coordinator.applySelection(selection));
    await _showStoredChoices();
  }

  HomeRequest get _choiceRequest => state.status == HomeStatus.connected
      ? HomeRequest.reconnect
      : HomeRequest.saveChoice;

  /// Closes the shown text. The card leaves when the catalog sees the saved row.
  Future<void> dismissAnnouncement() async {
    final row = state.subscription;
    final text = state.announcement;
    if (row == null || text == null) return;
    try {
      await _dismissAnnounce(row.id, text);
    } catch (error) {
      ygLogger('dismiss announcement failed (${error.runtimeType})');
    }
  }

  /// Measures the listed locations unless the tunnel is up. The results reach
  /// the screen through the catalog as each batch is saved.
  Future<void> measureLocations() async {
    if (_measuring || !state.canMeasure) return;
    _measuring = true;
    try {
      final listed = {for (final item in state.locations.all) item.id};
      await _pingLocations(
        state.catalog.servers.where((row) => listed.contains(row.id)).toList(),
        isCancelled: () => isClosed || !state.canMeasure,
      );
    } catch (error) {
      ygLogger('measure locations failed (${error.runtimeType})');
    } finally {
      _measuring = false;
    }
  }

  /// Connects from off, cancels a connection in progress, otherwise disconnects.
  Future<void> toggle(ConnectionActionRunner run) async {
    if (!state.canToggle) return;
    switch (state.status) {
      // Only this screen's own command is known to be cancellable. Whatever
      // else is connecting may be native, so a disconnect is what stops it.
      case HomeStatus.connecting when state.request == HomeRequest.connect:
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
    await _settings?.cancel();
  }
}
