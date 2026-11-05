import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/brand/login/controller.dart';
import 'package:onexray/brand/login/gate.dart';
import 'package:onexray/brand/login/page.dart';
import 'package:onexray/brand/permission/vpn_permission_page.dart';
import 'package:onexray/brand/router.dart';
import 'package:onexray/brand/subscription_link_flow.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/modal_route_observer.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/account/telegram_auth.dart';
import 'package:onexray/service/connect/connection_permissions.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/manager.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/shared/menu/short_cut/service.dart';
import 'package:onexray/service/shared/share/service.dart';

/// Starts the services, then hosts the tabs, or «Вход» while the device has
/// neither a session nor a subscription. Incoming links and the iOS Widget's
/// foreground actions are handled here because they need a ready UI:
/// `launchvpn://auth` returns go to the Telegram attempt waiting for them,
/// every other link to the subscription flow. A return to linking opens
/// «Аккаунт», which tells the outcome; a sign-in the system closed the App
/// during, which no «Вход» took back, opens one over the tabs.
class BrandShell extends StatefulWidget {
  const BrandShell({
    super.key,
    required this.navigationShell,
    required this.modals,
    this.initializeServices,
    this.shareService,
    this.openLink,
    this.account,
    this.watchSubscription,
  });

  final StatefulNavigationShell navigationShell;
  final AppModalRouteObserver modals;
  final Future<void> Function(BuildContext context)? initializeServices;
  final ShareService? shareService;
  final Future<void> Function(BuildContext, Uri)? openLink;
  final AccountService? account;

  /// Whether the device has a subscription; the database when null.
  final Stream<bool> Function()? watchSubscription;

  @override
  State<BrandShell> createState() => _BrandShellState();
}

class _BrandShellState extends State<BrandShell> {
  Future<void>? _servicesReady;
  late final _shareService = widget.shareService ?? ShareService();
  late final _account = widget.account ?? AccountService.instance;
  AccessGateController? _gate;
  StreamSubscription<void>? _gateSubscription;
  StreamSubscription<void>? _linkSubscription;
  IncomingAppLink? _activeLink;
  bool _attached = false;
  bool _drainScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _servicesReady ??= _initializeServices();
  }

  Future<void> _initializeServices() =>
      (widget.initializeServices ?? ServiceManager.serviceInit)(context);

  void _attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.modals.addListener(_scheduleDrain);
      _linkSubscription = _shareService.pendingAppLinksChanged.listen(
        (_) => _scheduleDrain(),
      );
      // Links received during startup precede this subscription.
      _scheduleDrain();
      ShortCutService().attach(_handleQuickAction);
    });
  }

  void _scheduleDrain() {
    if (!mounted || _drainScheduled) return;
    _drainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainScheduled = false;
      if (mounted) unawaited(_drain());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _drain() async {
    // Until the gate settles, nobody waits on «Вход» or the tabs.
    if (_activeLink != null ||
        widget.modals.hasPopupRoute ||
        _gate?.state == AccessGateState.checking) {
      return;
    }
    final event = _shareService.claimNextAppLink();
    if (event == null) return;
    _activeLink = event;
    try {
      final uri = event.uri;
      if (TelegramBrowserAuth.isReturn(uri)) {
        // Whoever started the attempt shows its outcome; a stray return is
        // dropped.
        if (_account.telegram.browser.handleReturn(uri)) {
          _showTelegramOutcome(uri);
        }
      } else {
        await (widget.openLink ?? openSubscriptionLink)(context, uri);
      }
    } catch (error) {
      ygLogger('open incoming link failed (${error.runtimeType})');
    } finally {
      _shareService.finishAppLink(event);
      if (identical(_activeLink, event)) _activeLink = null;
      if (mounted) _scheduleDrain();
    }
  }

  void _showTelegramOutcome(Uri uri) {
    final telegram = _account.telegram.browser;
    switch (TelegramBrowserAuth.purposeOf(uri)) {
      case TelegramAuthPurpose.link:
        widget.navigationShell.goBranch(BrandRoutes.accountBranch);
      case TelegramAuthPurpose.login
          when !_account.session.signedIn.value &&
              telegram.awaitsResume(TelegramAuthPurpose.login):
        unawaited(
          LoginPage.showOverTabs(
            context,
            account: _account,
            mode: LoginMode.signIn,
            signedIn: _signedInChanges(),
            links: _shareService,
          ),
        );
      case _:
    }
  }

  /// The session's [AccountSession.signedIn] as a stream, from the listen on.
  Stream<bool> _signedInChanges() {
    final signedIn = _account.session.signedIn;
    late final StreamController<bool> changes;
    void tell() => changes.add(signedIn.value);
    changes = StreamController<bool>(
      onListen: () => signedIn.addListener(tell),
      onCancel: () => signedIn.removeListener(tell),
    );
    return changes.stream;
  }

  Future<void> _handleQuickAction(ShortCutAction action) async {
    widget.navigationShell.goBranch(BrandRoutes.homeBranch);
    final coordinator = ConnectionCoordinator.instance;
    final command = switch (action) {
      ShortCutAction.startVpn => () => ConnectionPermissions(
        coordinator,
      ).connect(explain: () => VpnPermissionPage.show(context)),
      ShortCutAction.stopVpn => coordinator.disconnect,
      _ => null,
    };
    if (command == null || !mounted) return;
    await runConnectionAction(context, coordinator, command);
  }

  @override
  void dispose() {
    widget.modals.removeListener(_scheduleDrain);
    unawaited(_linkSubscription?.cancel());
    unawaited(_gateSubscription?.cancel());
    final active = _activeLink;
    if (active != null) _shareService.finishAppLink(active);
    ShortCutService().detach();
    unawaited(_gate?.close());
    super.dispose();
  }

  void _retry() {
    final servicesReady = _initializeServices();
    setState(() {
      _servicesReady = servicesReady;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _servicesReady,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return _loading;
      final l = AppLocalizations.of(context)!;
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(appFailureMessage(l, snapshot.error)),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('service-initialization-retry'),
                    onPressed: _retry,
                    child: Text(l.buttonRetry),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      _attach();
      // The subscription table is readable only once the services are up.
      final gate = _gate ??= AccessGateController(
        signedIn: _account.session.signedIn,
        hasSubscription: widget.watchSubscription?.call(),
      );
      _gateSubscription ??= gate.stream.listen((_) => _scheduleDrain());
      return BlocBuilder<AccessGateController, AccessGateState>(
        bloc: gate,
        builder: (context, state) => switch (state) {
          AccessGateState.checking => _loading,
          AccessGateState.login => LoginPage(
            account: _account,
            links: _shareService,
          ),
          AccessGateState.tabs => _tabs(l),
        },
      );
    },
  );

  static const _loading = Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );

  Widget _tabs(AppLocalizations l) {
    final shell = widget.navigationShell;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(LucideIcons.house),
            label: l.homeTab,
          ),
          NavigationDestination(
            icon: const Icon(LucideIcons.user),
            label: l.accountTab,
          ),
          NavigationDestination(
            icon: const Icon(LucideIcons.settings2),
            label: l.prototypeSettings,
          ),
        ],
      ),
    );
  }
}
