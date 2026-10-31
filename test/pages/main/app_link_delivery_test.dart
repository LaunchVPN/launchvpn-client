import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/adaptive_shell.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/main/modal_route_observer.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/share/service.dart';

void main() {
  testWidgets('cold link waits for ready UI and is consumed only once', (
    tester,
  ) async {
    final links = StreamController<Uri>.broadcast(sync: true);
    final share = ShareService.forTesting(
      appLinks: links.stream,
      receiveWidgetUri: (_) => false,
    );
    final ready = Completer<void>();
    final eventBus = AppEventBus();
    final received = <Uri>[];
    var finishLink = Completer<void>();
    final first = Uri.parse('launchvpn://sub/add?url=https://a.launch.tel');
    final second = Uri.parse('launchvpn://sub/add?url=https://b.launch.tel');
    share.startAppLinks();
    links.add(first);
    final modalObserver = AppModalRouteObserver();
    final router = GoRouter(
      initialLocation: '/connect',
      observers: [modalObserver],
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AdaptiveMainShell(
            navigationShell: shell,
            hasActiveModal: (_) => modalObserver.hasPopupRoute,
            modalChanges: modalObserver,
            shareService: share,
            openAppLink: (_, uri) {
              received.add(uri);
              return (finishLink = Completer<void>()).future;
            },
            initializeServices: (_) async {
              await share.init();
              await ready.future;
            },
          ),
          branches: [
            for (final primary in AppPrimaryDestination.values)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: primary.rootPath,
                    builder: (_, _) => const Text('home'),
                    routes: [
                      GoRoute(
                        path: AppPageDestination.serversImport.segment,
                        builder: (_, _) => const Scaffold(body: Text('manual')),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(() async {
      share.dispose();
      await links.close();
      router.dispose();
      await eventBus.close();
    });
    await tester.pumpWidget(
      BlocProvider.value(
        value: eventBus,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    expect(received, isEmpty);
    ready.complete();
    await tester.pumpAndSettle();
    expect(received, [first]);

    // A link already in progress is merged, and the next one waits for it.
    links.add(first);
    links.add(second);
    links.add(second);
    await tester.pumpAndSettle();
    expect(received, [first]);
    finishLink.complete();
    await tester.pumpAndSettle();
    expect(received, [first, second]);
    finishLink.complete();
    await tester.pumpAndSettle();

    // A manually opened import must finish before the cached link opens.
    unawaited(router.push('/connect/servers-import'));
    await tester.pumpAndSettle();
    links.add(first);
    await tester.pumpAndSettle();
    expect(received, [first, second]);
    router.pop();
    await tester.pumpAndSettle();
    expect(received, [first, second, first]);
    finishLink.complete();
    await tester.pumpAndSettle();

    // An open popup holds the link back until it closes.
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('home').first),
        builder: (_) => const AlertDialog(content: Text('manual-popup')),
      ),
    );
    await tester.pumpAndSettle();
    links.add(second);
    await tester.pumpAndSettle();
    expect(received, [first, second, first]);
    router.pop();
    await tester.pumpAndSettle();
    expect(received, [first, second, first, second]);
    finishLink.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
