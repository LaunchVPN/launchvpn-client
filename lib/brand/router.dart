import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/brand/account/page.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/home/page.dart';
import 'package:onexray/brand/settings/page.dart';
import 'package:onexray/brand/shell.dart';
import 'package:onexray/pages/main/modal_route_observer.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/shared/share/service.dart';

abstract final class BrandRoutes {
  static const home = '/home';
  static const account = '/account';
  static const settings = '/settings';
  static const homeBranch = 0;
  static const accountBranch = 1;
}

/// The whole navigable app. Upstream's pages are not registered, so nothing can
/// open them, including its manual import.
GoRouter createBrandRouter({
  HomeController? controller,
  Widget? home,
  Widget? accountTab,
  Widget? settings,
  Future<void> Function(BuildContext context)? initializeServices,
  ShareService? shareService,
  Future<void> Function(BuildContext, Uri)? openLink,
  AccountService? account,
  Stream<bool> Function()? watchSubscription,
}) {
  final modals = AppModalRouteObserver();
  // Home and Settings share it, so a mode chosen on either is one choice and one
  // reconnect. It lives as long as the app.
  late final shared = controller ?? HomeController();
  // «Аккаунт» and Home's «Лимит устройств» share the account's devices.
  late final session = account ?? AccountService.instance;
  late final addLink = (shareService ?? ShareService()).addAppLink;
  late final accountController = AccountController(
    account: session,
    openLink: addLink,
  );
  return GoRouter(
    initialLocation: BrandRoutes.home,
    observers: [modals],
    onException: (_, _, router) => router.go(BrandRoutes.home),
    routes: [
      StatefulShellRoute.indexedStack(
        // Forwarded branch events would overwrite the root modal state.
        notifyRootObserver: false,
        builder: (_, _, navigationShell) => BrandShell(
          navigationShell: navigationShell,
          modals: modals,
          initializeServices: initializeServices,
          shareService: shareService,
          openLink: openLink,
          account: account,
          watchSubscription: watchSubscription,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: BrandRoutes.home,
                builder: (_, _) =>
                    home ??
                    HomePage(controller: shared, account: accountController),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: BrandRoutes.account,
                builder: (_, _) =>
                    accountTab ??
                    AccountPage(
                      controller: accountController,
                      account: session,
                      openLink: addLink,
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: BrandRoutes.settings,
                builder: (_, _) =>
                    settings ?? BrandSettingsPage(controller: shared),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
