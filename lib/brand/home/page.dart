import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoSliverRefreshControl, RefreshIndicatorMode;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/brand/account/telegram_link_notice.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/home/device_limit.dart';
import 'package:onexray/brand/home/toggle.dart';
import 'package:onexray/brand/home/update_banner.dart';
import 'package:onexray/brand/external_link.dart';
import 'package:onexray/brand/locations/page.dart';
import 'package:onexray/brand/launch_reveal.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/pressable.dart';
import 'package:onexray/brand/settings/preset_page.dart';
import 'package:onexray/brand/settings/vpn_apps_page.dart';
import 'package:onexray/brand/permission/vpn_permission_page.dart';
import 'package:onexray/brand/pull.dart';
import 'package:onexray/brand/state_hero.dart';
import 'package:onexray/brand/swap.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/toast.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/distribution.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/connect/preset.dart';
import 'package:onexray/service/servers/locations.dart';
import 'package:onexray/service/servers/subscription/failure.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.account,
    this.distribution = AppDistribution.current,
  });

  final HomeController controller;

  /// The account's devices, which «Лимит устройств» lists.
  final AccountController account;

  /// Only an APK build offers a newer release and renewal on the site: a store
  /// updates the rest and takes no payment outside its own.
  final AppDistribution distribution;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Home without its free space, which the mockup splits evenly above and
  /// below the toggle and its text.
  static const _contentHeight = 382.0;

  /// The same plus a four-line announcement and the least space above the cards.
  static const _contentWithAnnouncementHeight = 528.0;

  /// The update banner and the space above it.
  static const _bannerHeight = 80.0;

  /// The header, the banner, the toggle with its text and the cards. As in the
  /// mockup's APK frame, the rest splits evenly above and below the toggle.
  static const _contentWithBannerHeight = 578.0;
  static const _minToggleGap = 24.0;

  /// From the header to a toast under it, as in the mockup.
  static const _toastGap = 32.0;

  HomeController get _controller => widget.controller;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
    _lifecycle = AppLifecycleListener(onResume: _controller.recheckExpiry);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    await runConnectionAction(context, _controller.coordinator, () async {
      try {
        await action();
      } catch (error) {
        // The error screen tells the cause; a toast would say it twice.
        if (!_controller.state.explains(error)) rethrow;
      }
    });
  }

  Future<void> _toggle() => _controller.toggle(_run, explain: _explain);

  /// «Обновить статус» and the pull on Home say at the top what the load
  /// found, under the header. A load that another change, such as a new
  /// link, superseded says nothing.
  Future<void> _refreshStatus() async {
    final l = AppLocalizations.of(context)!;
    final refreshed = await _controller.refreshStatus();
    if (refreshed == null || refreshed.result.superseded || !mounted) return;
    final result = refreshed.result;
    final (message, kind) = switch (refreshed.expiresAt) {
      _ when !result.success => (
        subscriptionFailureMessage(l, result.status, error: result.error),
        ToastKind.error,
      ),
      _ when _controller.state.expired => (
        l.homeExpiredNotRenewed,
        ToastKind.info,
      ),
      final end? => (l.homeRefreshedUntil(_day(l, end)), ToastKind.success),
      null => (l.homeRefreshed, ToastKind.success),
    };
    // The tabs keep Home alive, muting its tickers while another is shown;
    // that tab has no header to sit under. Read once, not depended on.
    final shown = TickerMode.getValuesNotifier(context).value.enabled;
    showBrandToast(
      context,
      message,
      kind: kind,
      top: shown ? _belowHeader : null,
    );
  }

  /// «24 декабря», with the year only when it is not this one.
  static String _day(AppLocalizations l, DateTime date) {
    final local = date.toLocal();
    final pattern = local.year == DateTime.now().year ? 'd MMMM' : 'd MMMM y';
    return DateFormat(pattern, l.localeName).format(local);
  }

  final _header = GlobalKey();

  /// Where a toast about the subscription starts, under the header.
  double get _belowHeader =>
      (_header.currentContext?.size?.height ?? 0) + _toastGap;

  Future<bool> _explain() => VpnPermissionPage.show(context);

  // Above the tab bar, as the mockup has it.
  Future<void> _openLocations() async {
    final chosen = await Navigator.of(context, rootNavigator: true)
        .push<Location>(
          MaterialPageRoute(
            builder: (_) => LocationsPage(controller: _controller),
          ),
        );
    if (chosen != null && mounted) {
      await _controller.selectLocation(chosen, _run, explain: _explain);
    }
  }

  /// Depends only on the height and the banner, so a status or an announcement
  /// never moves the toggle. It centers as in the mockup, higher only where an
  /// announcement would not fit otherwise.
  double _toggleGap(double height, {required bool banner}) {
    final (content, withAnnouncement) = banner
        ? (
            _contentWithBannerHeight,
            _contentWithAnnouncementHeight + _bannerHeight,
          )
        : (_contentHeight, _contentWithAnnouncementHeight);
    return max(
      _minToggleGap,
      min((height - content) / 2, height - withAnnouncement),
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: BrandTheme.statusBar,
    child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) =>
              BlocSelector<AppEventBus, AppEventBusState, AppUpdateInfo?>(
                selector: (bus) => widget.distribution == AppDistribution.apk
                    ? bus.appUpdateInfo
                    : null,
                builder: (context, update) =>
                    BlocSelector<
                      AccountController,
                      AccountState,
                      ({
                        bool ended,
                        bool refreshing,
                        bool trialWaitsOnTelegram,
                        bool linking,
                      })
                    >(
                      bloc: widget.account,
                      // A signed-in account without a subscription, its trial
                      // used, ended as well.
                      selector: (account) => (
                        ended: account.signedIn && account.inactive,
                        refreshing: account.refreshing,
                        trialWaitsOnTelegram: account.trialWaitsOnTelegram,
                        linking: account.linkingTelegram,
                      ),
                      builder: (context, account) =>
                          BlocBuilder<HomeController, HomeState>(
                            bloc: _controller,
                            builder: (context, state) {
                              final accountEnded =
                                  account.ended && state.subscription == null;
                              final expired =
                                  state.showsExpired || accountEnded;
                              // «Обновить статус» and the pull. Only the
                              // account can bring a subscription to an account
                              // that has none.
                              final refresh = accountEnded
                                  ? widget.account.refresh
                                  : state.subscription == null
                                  ? null
                                  : _refreshStatus;
                              return Column(
                                children: [
                                  // The pull happens under the header, which
                                  // stays where it is.
                                  Padding(
                                    key: _header,
                                    padding: const EdgeInsets.fromLTRB(
                                      BrandSpacing.page,
                                      8,
                                      BrandSpacing.page,
                                      0,
                                    ),
                                    child: _Header(
                                      // The expired screen's title says it
                                      // instead; the device limit's mockup
                                      // leaves it out.
                                      daysLeft:
                                          expired || state.showsDeviceLimit
                                          ? null
                                          : state.daysLeft(DateTime.now()),
                                    ),
                                  ),
                                  Expanded(
                                    child: _content(
                                      constraints,
                                      state,
                                      update: update,
                                      account: account,
                                      accountEnded: accountEnded,
                                      expired: expired,
                                      refresh: refresh,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                    ),
              ),
        ),
      ),
    ),
  );

  /// Everything under the header, which a pull refreshes the subscription
  /// from while there is one to refresh.
  Widget _content(
    BoxConstraints constraints,
    HomeState state, {
    required AppUpdateInfo? update,
    required ({
      bool ended,
      bool refreshing,
      bool trialWaitsOnTelegram,
      bool linking,
    })
    account,
    required bool accountEnded,
    required bool expired,
    required Future<void> Function()? refresh,
  }) => CustomScrollView(
    physics: refresh == null ? null : BrandPull.physics,
    slivers: [
      // Always here, so the content keeps its place among the slivers.
      CupertinoSliverRefreshControl(
        onRefresh: refresh,
        builder: refresh == null ? _noPull : _RefreshArc.build,
      ),
      SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            BrandSpacing.page,
            0,
            BrandSpacing.page,
            20,
          ),
          child: Column(
            children: [
              BrandReveal(
                child: update == null
                    ? null
                    : Padding(
                        key: ValueKey(update.latestVersion),
                        padding: const EdgeInsets.only(top: 20),
                        child: UpdateBanner(
                          update: update,
                          onUpdate: () =>
                              openExternalLink(update.releaseUri, 'release'),
                        ),
                      ),
              ),
              Expanded(
                child: BrandSwap.screen(
                  child: switch (_Screen.of(
                    state,
                    accountEnded: accountEnded,
                    expired: expired,
                    trialWaitsOnTelegram: account.trialWaitsOnTelegram,
                  )) {
                    _Screen.trialTelegram => _trialTelegramContent(
                      state,
                      linking: account.linking,
                    ),
                    _Screen.expired => _expiredContent(
                      state,
                      onRefresh: account.refreshing || state.refreshing
                          ? null
                          : refresh,
                    ),
                    _Screen.deviceLimit => _deviceLimitContent(state),
                    _Screen.failure => _failureContent(state, state.failure!),
                    _Screen.connection => _connectionContent(
                      state,
                      _toggleGap(constraints.maxHeight, banner: update != null),
                    ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  static Widget _noPull(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulledExtent,
    double refreshTriggerPullDistance,
    double refreshIndicatorExtent,
  ) => const SizedBox.shrink();

  /// The mockups' state screens: a centered explanation and the ways out, in
  /// place of the toggle and the cards.
  Widget _stateContent(_Screen screen, Widget hero, Widget actions) => Column(
    key: ValueKey(screen),
    children: [
      Expanded(child: Center(child: hero)),
      const SizedBox(height: 12),
      actions,
    ],
  );

  /// The error screen offers only the panel's support: null without its link.
  VoidCallback? _contactSupport(HomeState state) =>
      switch (state.subscription?.supportUrl) {
        null => null,
        _ => () => openSupport(state.subscription),
      };

  Widget _failureContent(HomeState state, HomeFailure failure) => _stateContent(
    _Screen.failure,
    _FailureHero(failure),
    _FailureActions(
      onRetry: _toggle,
      onChangeLocation: _openLocations,
      onContactSupport: _contactSupport(state),
    ),
  );

  Widget _expiredContent(HomeState state, {required VoidCallback? onRefresh}) {
    final l = AppLocalizations.of(context)!;
    final renews = widget.distribution == AppDistribution.apk;
    return _stateContent(
      _Screen.expired,
      StateHero.warning(
        icon: LucideIcons.calendar,
        title: l.homeExpiredTitle,
        body: renews ? l.homeExpiredBodyRenew : l.homeExpiredBody,
      ),
      _ExpiredActions(
        onRenew: renews
            ? () => openExternalLink(Uri.parse(Brand.renewalUrl), 'renewal')
            : null,
        onRefresh: onRefresh,
        onContactSupport: () => openSupport(state.subscription),
      ),
    );
  }

  /// A new account the trial waits on Telegram for: its email is at a
  /// domain anyone can make endless addresses on.
  Widget _trialTelegramContent(HomeState state, {required bool linking}) {
    final l = AppLocalizations.of(context)!;
    final buys = widget.distribution == AppDistribution.apk;
    return _stateContent(
      _Screen.trialTelegram,
      StateHero.accent(
        icon: LucideIcons.send,
        title: l.homeTrialTelegramTitle,
        body: l.homeTrialTelegramBody,
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          FilledButton.icon(
            style: BrandTheme.primaryButton,
            onPressed: linking ? null : _linkTelegram,
            icon: linking
                ? const ButtonProgressIndicator(size: 20)
                : const Icon(LucideIcons.send),
            label: Text(l.accountLinkTelegram),
          ),
          if (buys)
            TextButton.icon(
              style: BrandTheme.quietButton,
              onPressed: () =>
                  openExternalLink(Uri.parse(Brand.renewalUrl), 'renewal'),
              icon: const Icon(LucideIcons.externalLink),
              label: Text(l.homeTrialBuy),
            ),
          _SupportLink(onPressed: () => openSupport(state.subscription)),
        ],
      ),
    );
  }

  Future<void> _linkTelegram() async {
    final outcome = await widget.account.linkTelegram();
    if (mounted) await tellTelegramLink(context, outcome);
  }

  Widget _deviceLimitContent(HomeState state) => _stateContent(
    _Screen.deviceLimit,
    DeviceLimitHero(account: widget.account),
    DeviceLimitActions(
      account: widget.account,
      support: _SupportLink(onPressed: () => openSupport(state.subscription)),
    ),
  );

  Widget _connectionContent(HomeState state, double toggleGap) => Column(
    key: const ValueKey(_Screen.connection),
    children: [
      // Moves with the update banner as it opens or closes above.
      AnimatedContainer(
        duration: BrandMotion.of(context, BrandReveal.duration),
        curve: BrandMotion.smoothOut,
        height: toggleGap,
      ),
      _Hero(state: state, onToggle: _toggle),
      const SizedBox(height: 24),
      // Only the toggle follows a pull; the cards stay under the finger.
      Expanded(
        child: PinnedOnPull(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.location case final location?)
                LocationCard(
                  key: const ValueKey('home-location'),
                  location: location,
                  // "No answer" would contradict a tunnel that works.
                  delay: PingDelayConstants.isSuccessful(location.delay)
                      ? locationDelayLabel(
                          AppLocalizations.of(context)!,
                          location.delay,
                        )
                      : null,
                  onTap: _openLocations,
                  trailing: const Icon(
                    LucideIcons.chevronRight,
                    size: 20,
                    color: BrandColors.muted,
                  ),
                ),
              if (state.subscription != null) ...[
                const SizedBox(height: 20),
                _PresetSwitch(
                  presets: _controller.presets,
                  selected: state.preset,
                  onSelect: state.canChangeConnection
                      ? (preset) =>
                            choosePreset(context, _controller, preset, _run)
                      : null,
                ),
              ],
              BrandReveal(
                child: switch (state.announcement) {
                  null => null,
                  final text => Padding(
                    key: ValueKey(text),
                    padding: const EdgeInsets.only(top: 20),
                    child: _AnnouncementBanner(
                      text: text,
                      onClose: _controller.dismissAnnouncement,
                    ),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// What Home shows under the header, each giving way to the next with
/// [BrandSwap.screen].
enum _Screen {
  trialTelegram,
  expired,
  deviceLimit,
  failure,
  connection;

  static _Screen of(
    HomeState state, {
    required bool accountEnded,
    required bool expired,
    required bool trialWaitsOnTelegram,
  }) => switch (state) {
    _ when accountEnded && trialWaitsOnTelegram => trialTelegram,
    _ when expired => _Screen.expired,
    HomeState(showsDeviceLimit: true) => deviceLimit,
    HomeState(failure: _?) => failure,
    _ => connection,
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.daysLeft});

  static const _placeholderDays = 30;

  final int? daysLeft;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // A logo keeps its size when the system font grows. The launch mark
      // lands here.
      const LaunchMarkLanding(
        child: LaunchMark.logo(color: BrandColors.accent),
      ),
      const SizedBox(width: 8),
      const Text(
        Brand.wordmark,
        style: BrandText.wordmark,
        textScaler: TextScaler.noScaling,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          // The pill fades in and out over a placeholder that holds its
          // place, so its arrival does not move the toggle.
          child: BrandSwap(
            duration: BrandMotion.slow,
            reverseDuration: BrandMotion.medium,
            curve: BrandMotion.smoothOut,
            alignment: AlignmentDirectional.centerEnd,
            child: switch (daysLeft) {
              final days? => _DaysPill(key: const ValueKey('days'), days: days),
              null => const Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: _DaysPill(days: _placeholderDays),
              ),
            },
          ),
        ),
      ),
    ],
  );
}

class _DaysPill extends StatelessWidget {
  const _DaysPill({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(BrandRadii.full),
        border: Border.all(color: BrandColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.calendar, size: 14, color: BrandColors.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              days == 0 ? l.subscriptionPackageExpired : l.homeDaysLeft(days),
              style: BrandText.pill,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.state, required this.onToggle});

  final HomeState state;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final status = state.status;
    final title = switch (status) {
      HomeStatus.off || HomeStatus.failed => l.homeStatusOff,
      HomeStatus.connecting || HomeStatus.checking => l.homeStatusConnecting,
      HomeStatus.reconnecting => l.homeStatusReconnecting,
      HomeStatus.connected => l.homeStatusConnected,
      HomeStatus.disconnecting => l.homeStatusDisconnecting,
      HomeStatus.uncertain => l.homeStatusUncertain,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConnectToggle(
          key: const ValueKey('home-toggle'),
          label: title,
          state: switch (status) {
            HomeStatus.off || HomeStatus.failed => ConnectToggleState.off,
            HomeStatus.connected => ConnectToggleState.on,
            _ => ConnectToggleState.transitioning,
          },
          onPressed: state.canToggle ? onToggle : null,
        ),
        const SizedBox(height: 24),
        BrandSwap.text(
          child: Text(
            title,
            key: ValueKey(title),
            textAlign: TextAlign.center,
            style: BrandText.screenTitle,
          ),
        ),
        const SizedBox(height: 6),
        _Hint(state: state),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final message = switch (state.status) {
      // A failed attempt shows the error screen instead.
      HomeStatus.off || HomeStatus.failed =>
        state.subscription == null ? l.homeNoSubscription : l.homeHintOff,
      HomeStatus.connecting => l.homeHintConnecting,
      HomeStatus.checking => l.homeHintChecking,
      HomeStatus.reconnecting => l.homeHintReconnecting,
      HomeStatus.uncertain => l.homeHintUncertain,
      HomeStatus.connected || HomeStatus.disconnecting => null,
    };
    return BrandSwap.text(
      child: switch (state.status) {
        // Its clock ticks every second, which is not a change to swap.
        HomeStatus.connected => _ConnectedHint(
          key: const ValueKey(HomeStatus.connected),
          since: state.connectedSince,
        ),
        _ when message != null => Text(
          message,
          key: ValueKey(message),
          textAlign: TextAlign.center,
          style: BrandText.hint,
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _FailureHero extends StatelessWidget {
  const _FailureHero(this.failure);

  final HomeFailure failure;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (icon, title, body) = switch (failure) {
      HomeFailure.serverSilent => (
        LucideIcons.wifiOff,
        l.homeFailureServerTitle,
        l.homeFailureServerBody,
      ),
      HomeFailure.noServers => (
        LucideIcons.serverOff,
        l.homeFailureNoServersTitle,
        l.homeFailureNoServersBody,
      ),
      HomeFailure.other => (
        LucideIcons.circleAlert,
        l.homeFailureOtherTitle,
        l.homeFailureOtherBody,
      ),
    };
    return StateHero.danger(icon: icon, title: title, body: body);
  }
}

class _FailureActions extends StatelessWidget {
  const _FailureActions({
    required this.onRetry,
    required this.onChangeLocation,
    required this.onContactSupport,
  });

  final VoidCallback onRetry;
  final VoidCallback onChangeLocation;

  /// Null when the panel sent no support link.
  final VoidCallback? onContactSupport;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        FilledButton.icon(
          style: BrandTheme.primaryButton,
          onPressed: onRetry,
          icon: const Icon(LucideIcons.refreshCw),
          label: Text(l.buttonRetry),
        ),
        FilledButton.icon(
          style: BrandTheme.secondaryButton,
          onPressed: onChangeLocation,
          icon: const Icon(LucideIcons.globe),
          label: Text(l.homeChangeLocation),
        ),
        if (onContactSupport case final open?) _SupportLink(onPressed: open),
      ],
    );
  }
}

class _ExpiredActions extends StatelessWidget {
  const _ExpiredActions({
    required this.onRenew,
    required this.onRefresh,
    required this.onContactSupport,
  });

  /// Null in a store build, which offers no payment.
  final VoidCallback? onRenew;

  /// Null while the subscription loads, which the button shows with a spinner.
  final VoidCallback? onRefresh;

  /// The panel's support, or the bot's when it sent no link.
  final VoidCallback onContactSupport;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final refreshIcon = onRefresh == null
        ? const ButtonProgressIndicator(size: 20)
        : const Icon(LucideIcons.refreshCw);
    final refreshLabel = Text(l.homeExpiredRefresh);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (onRenew case final renew?) ...[
          FilledButton.icon(
            style: BrandTheme.primaryButton,
            onPressed: renew,
            icon: const Icon(LucideIcons.externalLink),
            label: Text(l.homeExpiredRenew),
          ),
          TextButton.icon(
            style: BrandTheme.quietButton,
            onPressed: onRefresh,
            icon: refreshIcon,
            label: refreshLabel,
          ),
        ] else
          FilledButton.icon(
            style: BrandTheme.primaryButton,
            onPressed: onRefresh,
            icon: refreshIcon,
            label: refreshLabel,
          ),
        _SupportLink(onPressed: onContactSupport),
      ],
    );
  }
}

class _SupportLink extends StatelessWidget {
  const _SupportLink({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: BrandTheme.linkButton,
    onPressed: onPressed,
    icon: const Icon(LucideIcons.messageCircle),
    label: Text(AppLocalizations.of(context)!.homeContactSupport),
  );
}

/// Counts from the session's own start, so reopening the app keeps the time.
class _ConnectedHint extends StatefulWidget {
  const _ConnectedHint({super.key, required this.since});

  final DateTime? since;

  @override
  State<_ConnectedHint> createState() => _ConnectedHintState();
}

class _ConnectedHintState extends State<_ConnectedHint> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsed(DateTime since) {
    final elapsed = DateTime.now().difference(since);
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(elapsed.inHours)}:${pad(elapsed.inMinutes % 60)}:'
        '${pad(elapsed.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.since;
    final hidden = AppLocalizations.of(context)!.homeIpHidden;
    return Text(
      since == null ? hidden : '${_elapsed(since)} · $hidden',
      textAlign: TextAlign.center,
      style: BrandText.timer,
    );
  }
}

class _AnnouncementBanner extends StatelessWidget {
  const _AnnouncementBanner({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  /// Inside the 1 px border, which makes the mockup's 15.
  static const _padding = 14.0;

  /// The icon lines up with the padding while its touch area stays comfortable.
  static const _closeTarget = 44.0;
  static const _closeIcon = 18.0;
  static const _closeInset = (_closeTarget - _closeIcon) / 2;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('home-announcement'),
    width: double.infinity,
    padding: const EdgeInsetsDirectional.only(
      start: _padding,
      top: _padding - _closeInset,
      end: _padding - _closeInset,
      bottom: _padding - _closeInset,
    ),
    decoration: BoxDecoration(
      color: BrandColors.accentSoft,
      borderRadius: BorderRadius.circular(BrandRadii.md),
      border: Border.all(color: BrandColors.accent),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: _closeInset),
          child: Icon(LucideIcons.bell, size: 20, color: BrandColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: _closeInset),
            child: Text(text, style: BrandText.banner),
          ),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context)!.homeAnnouncementClose,
          onPressed: onClose,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: _closeTarget,
            height: _closeTarget,
          ),
          icon: const Icon(
            LucideIcons.x,
            size: _closeIcon,
            color: BrandColors.muted,
          ),
        ),
      ],
    ),
  );
}

/// The segments over one highlight, which slides to the selected one.
class _PresetSwitch extends StatelessWidget {
  const _PresetSwitch({
    required this.presets,
    required this.selected,
    required this.onSelect,
  });

  /// Between segments and around them. Each segment keeps half of it on
  /// either side, so the highlight lines up with a segment by its share.
  static const _gap = 4.0;

  final List<ConnectionPreset> presets;
  final ConnectionPreset? selected;
  final ValueChanged<ConnectionPreset>? onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final duration = BrandMotion.of(context, BrandMotion.fast);
    final index = switch (selected) {
      final preset? => presets.indexOf(preset),
      null => -1,
    };
    const half = EdgeInsets.symmetric(horizontal: _gap / 2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _gap / 2, vertical: _gap),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(BrandRadii.control),
        border: Border.all(color: BrandColors.line),
      ),
      child: IntrinsicHeight(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: index < 0 ? 0 : 1,
                duration: duration,
                child: AnimatedAlign(
                  duration: duration,
                  curve: BrandMotion.smoothOut,
                  alignment: AlignmentDirectional(
                    presets.length < 2
                        ? 0
                        : -1 + 2 * max(index, 0) / (presets.length - 1),
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / presets.length,
                    heightFactor: 1,
                    child: Padding(
                      padding: half,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: BrandColors.accentSoft,
                          borderRadius: BorderRadius.circular(
                            BrandRadii.segment,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final preset in presets)
                  Expanded(
                    child: Padding(
                      padding: half,
                      child: _PresetSegment(
                        label: presetLabel(l, preset),
                        selected: preset == selected,
                        onTap: onSelect == null
                            ? null
                            : () => onSelect!(preset),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetSegment extends StatelessWidget {
  const _PresetSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    selected: selected,
    label: label,
    child: Pressable(
      onTap: onTap,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: AnimatedDefaultTextStyle(
            duration: BrandMotion.of(context, BrandMotion.fast),
            curve: BrandMotion.smoothOut,
            style: selected ? BrandText.selectedPreset : BrandText.preset,
            textAlign: TextAlign.center,
            child: Text(label),
          ),
        ),
      ),
    ),
  );
}

/// Under the header while Home is pulled: an arc that closes as the pull
/// goes on and turns while the subscription loads.
class _RefreshArc extends StatefulWidget {
  const _RefreshArc({required this.mode, required this.progress});

  static Widget build(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulledExtent,
    double refreshTriggerPullDistance,
    double refreshIndicatorExtent,
  ) => _RefreshArc(
    mode: mode,
    progress: BrandPull.progress(
      mode,
      pulledExtent,
      refreshTriggerPullDistance,
    ),
  );

  final RefreshIndicatorMode mode;
  final double progress;

  @override
  State<_RefreshArc> createState() => _RefreshArcState();
}

class _RefreshArcState extends State<_RefreshArc>
    with SingleTickerProviderStateMixin {
  static const _size = 18.0;

  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get _loading => widget.mode == RefreshIndicatorMode.refresh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(_RefreshArc old) {
    super.didUpdateWidget(old);
    _follow();
  }

  void _follow() {
    if (_loading && !BrandMotion.reduced(context)) {
      if (!_turn.isAnimating) unawaited(_turn.repeat());
    } else {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: PullFade(
      mode: widget.mode,
      progress: widget.progress,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _turn,
            child: CustomPaint(
              size: const Size.square(_size),
              painter: _ArcPainter(widget.progress),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            AppLocalizations.of(context)!.homeRefreshing,
            style: BrandText.caption,
          ),
        ],
      ),
    ),
  );
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.progress);

  /// The mockup's arc leaves a fifth of the circle open.
  static const _sweep = 0.8 * 2 * pi;

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    canvas.drawArc(
      (Offset.zero & size).deflate(stroke / 2),
      -pi / 2,
      _sweep * progress,
      false,
      Paint()
        ..color = BrandColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => progress != old.progress;
}
