import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/brand/home/page.dart';
import 'package:onexray/brand/settings/page.dart';
import 'package:onexray/brand/shell.dart';
import 'package:onexray/pages/main/modal_route_observer.dart';
import 'package:onexray/service/shared/share/service.dart';

abstract final class BrandRoutes {
  static const home = '/home';
  static const settings = '/settings';
  static const homeBranch = 0;
}

/// The whole navigable app. Upstream's pages are not registered, so nothing can
/// open them, including its manual import.
GoRouter createBrandRouter({
  Widget home = const HomePage(),
  Future<void> Function(BuildContext context)? initializeServices,
  ShareService? shareService,
  Future<void> Function(BuildContext, Uri)? openLink,
}) {
  final modals = AppModalRouteObserver();
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
        ),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: BrandRoutes.home, builder: (_, _) => home)],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: BrandRoutes.settings,
                builder: (_, _) => const BrandSettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
