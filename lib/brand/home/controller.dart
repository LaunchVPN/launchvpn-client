import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/connect/connection_permissions.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/connection_check.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/shared/apple_widget/service.dart';
import 'package:onexray/service/connect/keep_vpn_on.dart';
import 'package:onexray/service/connect/preset.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/locations.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';
import 'package:onexray/service/shared/ping/service.dart';

enum HomeStatus {
  off,
  connecting,
  reconnecting,

  /// The tunnel is up, and no check has got through it yet.
  checking,
  connected,
  disconnecting,
  failed,

  /// A command failed and the tunnel may still be up.
  uncertain,
}

enum HomeRequest { connect, disconnect, reconnect, saveChoice }

/// Why the last attempt failed, as the error screen tells it.
enum HomeFailure {
  /// No server of the group answered, before the start or after the
  /// running session went silent.
  serverSilent,

  /// The selection has no servers to connect to.
  noServers,

  /// Any other cause, which only the toast names.
  other;

  static final _causes = {
    ConnectionResolutionFailure.insufficientHealthyServers.name: serverSilent,
    ConnectionResolutionFailure.selectionUnavailable.name: noServers,
  };

  static HomeFailure of(String? issue) => _causes[issue] ?? other;

  /// Whether the screen's own text names the cause.
  bool get namesCause => this != other;
}

/// Runs a connection command and reports its failure to the user.
typedef ConnectionActionRunner = Future<void> Function(
  Future<void> Function() action,
);

typedef LocationPing = Future<void> Function(
  List<CoreConfigData> rows, {
  bool Function()? isCancelled,
});

typedef AnnouncementDismissal = Future<void> Function(int subId, String text);

/// The apps Android lists, as the bridge returns them.
typedef InstalledApps = Future<List<AndroidAppInfo>> Function();

/// Whether «Локации» can measure now.
enum MeasureReadiness {
  /// The tunnel is off, or lets measurements past it.
  ready,

  /// A connection is coming up or going down; it can once that ends.
  waiting,

  /// The running tunnel captures all traffic, so no socket gets past it.
  onlyWithVpnOff,
}

class HomeState {
  HomeState({
    this.view = const ConnectionView(),
    ServerCatalog? catalog,
    this.request,
    this.restoring = false,
    this.preset,
    this.vpnApps = const [],
    this.keepVpnOn,
    this.selection,
    this.expired = false,
    this.refreshing = false,
    this.deviceLimit = false,
    this.check,
    this.measuring = const {},
    this.queued = const {},
  }) : catalog = catalog ?? ServerCatalog();

  final ConnectionView view;
  final ServerCatalog catalog;

  /// Null until the saved preset is read, and for a mode the App does not
  /// offer, such as a custom route.
  final ConnectionPreset? preset;

  /// What «Приложения» sends through the VPN, kept under the other modes.
  final List<String> vpnApps;

  /// «Не отключать VPN» on iOS. Null until the saved choices are read.
  final bool? keepVpnOn;

  /// Null until the saved choices are read.
  final ServerSelection? selection;

  // A command may wait for permission or the serial queue before it publishes
  // a phase. The tap is acknowledged at once without claiming a native state.
  final HomeRequest? request;

  /// The session fell from connected to connecting, so the system is restoring
  /// it. The same phase after off is a start from outside the app.
  final bool restoring;

  /// The subscription's expiry has passed. Home shows «Подписка закончилась»
  /// instead of the toggle, and no tunnel stays up.
  final bool expired;

  /// «Обновить статус» is loading the subscription.
  final bool refreshing;

  /// The panel refused this device: the subscription has all its devices.
  final bool deviceLimit;

  /// Null where the App does not check the connection, which then counts as
  /// soon as the tunnel is up.
  final ConnectionCheckView? check;

  /// The locations in a sweep, or whose saved delay the catalog does not list
  /// yet, by row ID.
  final Set<int> measuring;

  /// The locations asked for mid-transition, measured once it ends.
  final Set<int> queued;

  /// Whether [location] shows that it is being measured. A sweep forgets the
  /// last delay a moment after it starts, so until then that one still shows.
  bool showsMeasuring(Location location) =>
      queued.contains(location.id) ||
      (measuring.contains(location.id) &&
          location.delay == PingDelayConstants.unknown);

  /// «Лимит устройств» in place of the toggle, once the tunnel is off. An
  /// ended subscription explains itself first.
  bool get showsDeviceLimit => deviceLimit && _tunnelOff && !showsExpired;

  /// The screen waits for the tunnel to go off. Until then the toggle shows
  /// the disconnect, or a failed one to retry.
  bool get showsExpired => expired && _tunnelOff;

  bool get _tunnelOff =>
      status == HomeStatus.off || status == HomeStatus.failed;

  HomeStatus get status => switch (request) {
    HomeRequest.disconnect => HomeStatus.disconnecting,
    HomeRequest.connect => HomeStatus.connecting,
    HomeRequest.reconnect => HomeStatus.reconnecting,
    HomeRequest.saveChoice || null => _reported,
  };

  /// What the coordinator reports, whatever command is waiting to start.
  /// A restart after the server went silent reads as one reconnection, until
  /// a check gets through the new session.
  HomeStatus get _reported => switch (view.phase) {
    _ when _switching => HomeStatus.reconnecting,
    ConnectionPhase.connected =>
      _reached ? HomeStatus.connected : HomeStatus.checking,
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

  bool get _switching =>
      check?.stage == ConnectionCheckStage.switching &&
      view.phase != ConnectionPhase.disconnected &&
      view.phase != ConnectionPhase.failed;

  /// Whether a check got through the running session.
  bool get _reached => switch ((check, view.runtime)) {
    (final check?, final runtime?) => check.reached(runtime),
    _ => true,
  };

  /// Set while Home shows the error screen instead of the toggle.
  HomeFailure? get failure =>
      status == HomeStatus.failed ? HomeFailure.of(view.issue) : null;

  /// Whether the error screen names the cause of [error] once its command
  /// ends, so a toast would only repeat it. A generic failure keeps the toast,
  /// the only place its specific cause appears.
  bool explains(Object error) =>
      _reported == HomeStatus.failed &&
      identical(view.error, error) &&
      HomeFailure.of(view.issue).namesCause;

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
      selection != null &&
      request == null &&
      const {
        HomeStatus.off,
        HomeStatus.failed,
        HomeStatus.checking,
        HomeStatus.connected,
      }.contains(status);

  /// Measurements dial past a running tunnel, unless it captures all traffic.
  /// One mid-transition would race the tunnel coming up or going down.
  MeasureReadiness get measureReadiness => switch (status) {
    _ when request != null => MeasureReadiness.waiting,
    HomeStatus.off || HomeStatus.failed => MeasureReadiness.ready,
    HomeStatus.checking || HomeStatus.connected
        when view.runtime?.request.tun?.includeAllNetworks ?? false =>
      MeasureReadiness.onlyWithVpnOff,
    HomeStatus.checking || HomeStatus.connected => MeasureReadiness.ready,
    _ => MeasureReadiness.waiting,
  };

  late final LocationList locations = LocationList.from(catalog);

  /// Whether the stored selection already names [location]. An automatic one
  /// stands for the first location.
  bool stores(Location location) => selection?.kind == SelectionKind.server
      ? selection!.id == location.id
      : location.id == locations.first?.id;

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
  ///
  /// Once a tunnel is starting, the delay is only what its own check
  /// measured, never the list's last one, which was taken outside it.
  Location? get location {
    final shown = _location;
    final check = this.check;
    if (shown == null || check == null || _tunnelOff) return shown;
    return shown.withDelay(
      status == HomeStatus.connected
          ? check.delayMs ?? PingDelayConstants.unknown
          : PingDelayConstants.unknown,
    );
  }

  Location? get _location {
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
  int? daysLeft(DateTime now) => switch (subscription) {
    final row? => SubscriptionUserInfo.fromSubscription(row)?.daysLeft(now),
    null => null,
  };

  HomeState copyWith({
    ConnectionView? view,
    ServerCatalog? catalog,
    bool? restoring,
    ConnectionPreset? Function()? preset,
    List<String>? vpnApps,
    bool? keepVpnOn,
    ServerSelection? selection,
    bool? expired,
    bool? refreshing,
    bool? deviceLimit,
    ConnectionCheckView? check,
    Set<int>? measuring,
    Set<int>? queued,
  }) => HomeState(
    view: view ?? this.view,
    catalog: catalog ?? this.catalog,
    request: request,
    restoring: restoring ?? this.restoring,
    preset: preset == null ? this.preset : preset(),
    vpnApps: vpnApps ?? this.vpnApps,
    keepVpnOn: keepVpnOn ?? this.keepVpnOn,
    selection: selection ?? this.selection,
    expired: expired ?? this.expired,
    refreshing: refreshing ?? this.refreshing,
    deviceLimit: deviceLimit ?? this.deviceLimit,
    check: check ?? this.check,
    measuring: measuring ?? this.measuring,
    queued: queued ?? this.queued,
  );

  HomeState _withRequest(HomeRequest? request) => HomeState(
    view: view,
    catalog: catalog,
    request: request,
    restoring: restoring,
    preset: preset,
    vpnApps: vpnApps,
    keepVpnOn: keepVpnOn,
    selection: selection,
    expired: expired,
    refreshing: refreshing,
    deviceLimit: deviceLimit,
    check: check,
    measuring: measuring,
    queued: queued,
  );
}

/// What a load of the subscription brought, with its end after a success,
/// unless the panel sets none.
typedef SubscriptionRefreshed = ({
  SubscriptionRefreshResult result,
  DateTime? expiresAt,
});

/// Hands the iOS Widget what Home shows next to the status.
typedef WidgetContextPublisher = Future<void> Function({
  required Location? location,
  required ConnectionPreset? preset,
  required DateTime? expiresAt,
});

class HomeController extends PageCubit<HomeState> {
  HomeController({
    AppDatabase? database,
    ConnectionCoordinator? coordinator,
    LocationPing? pingLocations,
    AnnouncementDismissal? dismissAnnounce,
    SubscriptionRefresh? refreshSubscription,
    ConnectionPlatform? platform,
    InstalledApps? installedApps,
    ValueListenable<bool>? deviceLimit,
    WidgetContextPublisher? widgetContext,
    ValueListenable<ConnectionCheckView>? connectionCheck,
  }) : _db = database ?? AppDatabase(),
       _check = connectionCheck ?? ConnectionCheck.instance?.view,
       _widgetContext = widgetContext ?? AppleWidgetService().setContext,
       installedApps = installedApps ?? AppHostApi().getInstalledApps,
       _platform = platform ?? connectionPlatform,
       coordinator = coordinator ?? ConnectionCoordinator.instance,
       _pingLocations = pingLocations ?? PingService().pingLocations,
       _dismissAnnounce =
           dismissAnnounce ?? SubscriptionService().dismissAnnounce,
       _refreshSubscription =
           refreshSubscription ??
           SubscriptionService().refreshSubscriptionResult,
       _deviceLimit = deviceLimit ?? SubscriptionService().deviceLimitReached,
       super(HomeState()) {
    this.coordinator.state.addListener(_connectionChanged);
    _connectionChanged();
    _deviceLimit.addListener(_deviceLimitChanged);
    _deviceLimitChanged();
    _check?.addListener(_checkChanged);
    _checkChanged();
  }

  final AppDatabase _db;
  final ConnectionPlatform _platform;

  /// What «Приложения через VPN» lists.
  final InstalledApps installedApps;
  final ConnectionCoordinator coordinator;
  late final _permissions = ConnectionPermissions(coordinator);
  final LocationPing _pingLocations;
  final AnnouncementDismissal _dismissAnnounce;
  final SubscriptionRefresh _refreshSubscription;
  final ValueListenable<bool> _deviceLimit;
  final WidgetContextPublisher _widgetContext;
  final ValueListenable<ConnectionCheckView>? _check;
  StreamSubscription<ServerCatalog>? _catalog;
  StreamSubscription<void>? _settings;
  Timer? _expiry;

  /// The sweep each location is in, until it ends.
  final _sweeps = <int, Future<void>>{};

  /// Locations a sweep saved a delay for that the catalog does not list yet.
  final _unlisted = <int>{};

  /// Locations asked for mid-transition.
  final _queued = <int>{};

  /// An expiry this close gets a timer, and so does a running tunnel, which
  /// checks again at least this often. Otherwise a later expiry is checked
  /// when the subscription refreshes or the App returns.
  static const _expiryWatch = Duration(days: 1);

  /// What Home and «Режим» offer on this device.
  List<ConnectionPreset> get presets => ConnectionPreset.offeredOn(_platform);

  /// Settings offers «Не отключать VPN» on iOS only.
  bool get offersKeepVpnOn => KeepVpnOn.offeredOn(_platform);

  /// The iOS Widget shows the same location, mode and end date as Home.
  @override
  void onChange(Change<HomeState> change) {
    super.onChange(change);
    final next = change.nextState;
    unawaited(
      _widgetContext(
        location: next.location,
        preset: next.preset,
        expiresAt: switch (next.subscription) {
          final row? => SubscriptionUserInfo.fromSubscription(row)?.expiresAt,
          null => null,
        },
      ),
    );
    if (_queued.isNotEmpty &&
        next.measureReadiness != MeasureReadiness.waiting) {
      // The new state is not current until this returns.
      scheduleMicrotask(_measureQueued);
    }
  }

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
    // A tunnel that came up needs its expiry watched.
    _checkExpiry(state.subscription);
    _stopIfExpired();
  }

  void _checkChanged() {
    if (_check case final check?) emit(state.copyWith(check: check.value));
  }

  void _deviceLimitChanged() =>
      emit(state.copyWith(deviceLimit: _deviceLimit.value));

  Future<void> initialize() async {
    _catalog ??= ServerCatalog.watch(_db).listen(
      (catalog) {
        _dropListed(catalog);
        _showMeasuring(catalog: catalog);
        _checkExpiry(catalog.sources.lastOrNull);
      },
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
          preset: () => ConnectionPreset.of(stored, platform: _platform),
          vpnApps: stored.vpnApps,
          keepVpnOn: stored.keepVpnOn,
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
    ConnectionPreset preset,
    ConnectionActionRunner run,
  ) async {
    if (!state.canChangeConnection || preset == state.preset) return;
    await _saveChoice(
      state.copyWith(preset: () => preset),
      _choiceRequest,
      run,
      preset.applyTo,
    );
  }

  /// Saves what «Приложения» sends through the VPN, and with [select] also
  /// picks that mode. The running tunnel reconnects only when the change
  /// reaches it. An empty list cannot run, so it returns to «Умный».
  Future<void> saveVpnApps(
    List<String> apps,
    ConnectionActionRunner run, {
    bool select = false,
  }) async {
    final current = state.preset;
    if (!state.canChangeConnection) return;
    final preset = apps.isEmpty
        ? (current == ConnectionPreset.apps ? ConnectionPreset.smart : current)
        : (select ? ConnectionPreset.apps : current);
    if (preset == current && _sameApps(apps, state.vpnApps)) return;
    final restart = preset != current || preset == ConnectionPreset.apps;
    await _saveChoice(
      state.copyWith(preset: () => preset, vpnApps: List.unmodifiable(apps)),
      restart ? _choiceRequest : HomeRequest.saveChoice,
      run,
      (stored) =>
          preset?.applyTo(stored.withVpnApps(apps)) ?? stored.withVpnApps(apps),
      restart: restart,
    );
  }

  /// Saves «Не отключать VPN». Like the other tunnel settings, it reaches the
  /// system with the next connection, so a running tunnel keeps going.
  Future<void> saveKeepVpnOn(bool value, ConnectionActionRunner run) async {
    if (!state.canChangeConnection || value == state.keepVpnOn) return;
    await _saveChoice(
      state.copyWith(keepVpnOn: value),
      HomeRequest.saveChoice,
      run,
      (stored) => stored.withKeepVpnOn(value),
      restart: false,
    );
  }

  /// Shows [shown] at once, stores [change] and shows what was stored, so a
  /// failed save puts the previous choice back.
  Future<void> _saveChoice(
    HomeState shown,
    HomeRequest request,
    ConnectionActionRunner run,
    ConnectionConfiguration Function(ConnectionConfiguration stored) change, {
    bool restart = true,
  }) async {
    emit(shown);
    await _perform(
      request,
      run,
      () => coordinator.applyChange(change, restart: restart),
    );
    await _showStoredChoices();
  }

  static bool _sameApps(List<String> a, List<String> b) =>
      const SetEquality<String>().equals(a.toSet(), b.toSet());

  /// Saves the location, with the same immediate reconnect as a preset. After
  /// a failed attempt it also connects, the same location included, since the
  /// person came to fix the connection.
  Future<void> selectLocation(
    Location location,
    ConnectionActionRunner run, {
    required VpnPermissionExplanation explain,
  }) async {
    final retry = state.status == HomeStatus.failed;
    // A retry compares with what is stored: a fixed choice whose row is gone
    // shows the first location without storing it.
    final unchanged = retry
        ? state.stores(location)
        : location.id == state.selectedLocation?.id;
    if (state.canChangeConnection && !unchanged) {
      final request = _choiceRequest;
      final selection = ServerSelection.server(location.id);
      emit(state.copyWith(selection: selection));
      await _perform(request, run, () => coordinator.applySelection(selection));
      await _showStoredChoices();
    }
    // A choice that was not saved would retry the location that just failed.
    if (retry && state.selectedLocation?.id == location.id) {
      await toggle(run, explain: explain);
    }
  }

  HomeRequest get _choiceRequest =>
      state.view.phase == ConnectionPhase.connected
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

  /// Follows [row]'s expiry. An expiry turns the tunnel off; a renewal after
  /// it connects, as «Подписка закончилась» promises.
  void _checkExpiry(SubscriptionData? row) {
    _expiry?.cancel();
    if (isClosed) return;
    final now = DateTime.now();
    final info = row == null
        ? null
        : SubscriptionUserInfo.fromSubscription(row);
    final expired = info?.isExpired(now) ?? false;
    if (info?.expiresAt case final expiresAt? when !expired) {
      final left = expiresAt.difference(now);
      if (left <= _expiryWatch || !state._tunnelOff) {
        _expiry = Timer(
          left < _expiryWatch ? left : _expiryWatch,
          recheckExpiry,
        );
      }
    }
    if (expired == state.expired) return;
    emit(state.copyWith(expired: expired));
    if (expired) {
      _stopIfExpired();
    } else {
      unawaited(_connectAfterRenewal());
    }
  }

  /// A timer pauses while the device sleeps, so the screen checks again when
  /// the App returns.
  void recheckExpiry() => _checkExpiry(state.subscription);

  /// Without VPN consent only a tap may bring up the prompt, so the toggle
  /// waits for one. A removed subscription is no renewal.
  Future<void> _connectAfterRenewal() async {
    if (state.subscription == null || !state._tunnelOff) return;
    if (coordinator.state.value.issue == 'permissionRequired') return;
    await _perform(HomeRequest.connect, _logFailure, coordinator.connect);
  }

  /// The panel no longer serves an expired subscription, so a tunnel through
  /// it would only keep the phone offline.
  void _stopIfExpired() {
    if (!state.expired) return;
    switch (state.status) {
      case HomeStatus.off || HomeStatus.failed || HomeStatus.disconnecting:
        break;
      case HomeStatus.connecting when state.request == HomeRequest.connect:
        coordinator.cancel();
      default:
        unawaited(
          _perform(HomeRequest.disconnect, _logFailure, coordinator.disconnect),
        );
    }
  }

  /// Runs a command nobody tapped, so no toast reports its failure.
  static Future<void> _logFailure(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      ygLogger('automatic connection command failed (${error.runtimeType})');
    }
  }

  /// «Обновить статус» and the pull on Home: loads the subscription the way
  /// the interval update does. A failed load keeps the stored data. A renewal
  /// connects at once. Null when there is nothing to load, a load is already
  /// running, or a link replaced the subscription meanwhile, which its own
  /// import reports.
  Future<SubscriptionRefreshed?> refreshStatus() async {
    final row = state.subscription;
    if (row == null || state.refreshing) return null;
    emit(state.copyWith(refreshing: true));
    try {
      final result = await _refreshSubscription(row);
      if (row.id != state.subscription?.id) return null;
      // The catalog may not have seen the new row yet.
      if (!result.success) return (result: result, expiresAt: null);
      final fresh = await _db.subscriptionDao.searchRow(row.id);
      _checkExpiry(fresh);
      return (
        result: result,
        expiresAt: fresh == null
            ? null
            : SubscriptionUserInfo.fromSubscription(fresh)?.expiresAt,
      );
    } finally {
      emit(state.copyWith(refreshing: false));
    }
  }

  /// Measures [only] that location, or every listed one. A location already
  /// in a sweep stays in it, and the call returns once all of them are done.
  /// The results reach the screen through the catalog as each is saved.
  ///
  /// Mid-transition the locations wait for it to end and the call returns at
  /// once. A tunnel that captures all traffic leaves nothing to measure.
  Future<void> measureLocations({Location? only}) {
    final ids = only == null
        ? [for (final item in state.locations.all) item.id]
        : [only.id];
    switch (state.measureReadiness) {
      case MeasureReadiness.ready:
        return _measure(ids);
      case MeasureReadiness.waiting:
        _queued.addAll(ids);
        _showMeasuring();
      case MeasureReadiness.onlyWithVpnOff:
        break;
    }
    return Future.value();
  }

  /// Measures what waited for a transition, once it ends. A location still in
  /// the sweep the transition stopped waits for that sweep to return.
  void _measureQueued() {
    if (isClosed || _queued.isEmpty) return;
    switch (state.measureReadiness) {
      case MeasureReadiness.waiting:
        return;
      case MeasureReadiness.ready:
        final ids = [
          for (final id in _queued)
            if (!_sweeps.containsKey(id)) id,
        ];
        _queued.removeAll(ids);
        if (ids.isNotEmpty) unawaited(_measure(ids));
      case MeasureReadiness.onlyWithVpnOff:
        _queued.clear();
        _showMeasuring();
    }
  }

  Future<void> _measure(List<int> ids) {
    final fresh = {
      for (final id in ids)
        if (!_sweeps.containsKey(id)) id,
    };
    if (fresh.isNotEmpty) {
      final done = Completer<void>();
      for (final id in fresh) {
        _sweeps[id] = done.future;
      }
      _unlisted.removeAll(fresh);
      _showMeasuring();
      unawaited(_sweep(fresh).whenComplete(done.complete));
    }
    return Future.wait({for (final id in ids) ?_sweeps[id]});
  }

  Future<void> _sweep(Set<int> ids) async {
    var stopped = false;
    try {
      await _pingLocations(
        state.catalog.servers.where((row) => ids.contains(row.id)).toList(),
        isCancelled: () => stopped =
            stopped ||
            isClosed ||
            state.measureReadiness != MeasureReadiness.ready,
      );
    } catch (error) {
      ygLogger('measure locations failed (${error.runtimeType})');
    }
    try {
      final saved = {
        for (final row in await _db.coreConfigDao.allActiveServerRows())
          if (ids.contains(row.id) && row.delay != PingDelayConstants.unknown)
            row.id,
      };
      _unlisted.addAll(saved);
      _dropListed(state.catalog);
      // What a transition left unmeasured resumes once it ends.
      if (stopped) _queued.addAll(ids.difference(saved));
    } catch (error) {
      ygLogger('read measured locations failed (${error.runtimeType})');
    }
    ids.forEach(_sweeps.remove);
    _showMeasuring();
    _measureQueued();
  }

  /// A saved delay reaches the catalog a moment after its sweep ends, and the
  /// location counts as measuring until then. A location the catalog no longer
  /// has is done as well.
  void _dropListed(ServerCatalog catalog) => _unlisted.removeWhere(
    (id) =>
        catalog.servers.firstWhereOrNull((row) => row.id == id)?.delay !=
        PingDelayConstants.unknown,
  );

  void _showMeasuring({ServerCatalog? catalog}) {
    if (isClosed) return;
    emit(
      state.copyWith(
        catalog: catalog,
        measuring: Set.unmodifiable({..._sweeps.keys, ..._unlisted}),
        queued: Set.unmodifiable(_queued),
      ),
    );
  }

  /// Connects from off, cancels a connection in progress, otherwise disconnects.
  /// A connection without VPN permission may first [explain] the system prompt.
  Future<void> toggle(
    ConnectionActionRunner run, {
    required VpnPermissionExplanation explain,
  }) async {
    if (!state.canToggle) return;
    switch (state.status) {
      // Only this screen's own command is known to be cancellable. Whatever
      // else is connecting may be native, so a disconnect is what stops it.
      case HomeStatus.connecting when state.request == HomeRequest.connect:
        coordinator.cancel();
      case HomeStatus.off || HomeStatus.failed:
        await _perform(
          HomeRequest.connect,
          run,
          () => _permissions.connect(explain: explain),
        );
      case HomeStatus.disconnecting:
        break;
      default:
        await _perform(HomeRequest.disconnect, run, coordinator.disconnect);
    }
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
    _deviceLimit.removeListener(_deviceLimitChanged);
    _check?.removeListener(_checkChanged);
    _expiry?.cancel();
    await _catalog?.cancel();
    await _settings?.cancel();
  }
}
