import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/app.dart';
import 'package:onexray/brand/router.dart';
import 'package:onexray/service/shared/share/service.dart';

final _first = Uri.parse('launchvpn://sub/add?url=https://a.launch.tel');
final _second = Uri.parse('launchvpn://sub/add?url=https://b.launch.tel');

void main() {
  late StreamController<Uri> links;
  late ShareService share;
  Completer<void>? ready;
  late List<Uri> opened;
  late Completer<void> finishLink;

  // Called inside each test: streams and timers must belong to its fake clock.
  void prepare() {
    links = StreamController<Uri>.broadcast(sync: true);
    addTearDown(() async {
      share.dispose();
      await links.close();
    });
    share = ShareService.forTesting(
      appLinks: links.stream,
      receiveWidgetUri: (_) => false,
    );
    ready = null;
    opened = [];
    finishLink = Completer();
    share.startAppLinks();
  }

  GoRouter router() => createBrandRouter(
    home: const Text('home-body'),
    settings: const Text('settings-body'),
    shareService: share,
    initializeServices: (_) async {
      await share.init();
      await ready?.future;
    },
    openLink: (_, uri) {
      opened.add(uri);
      return (finishLink = Completer<void>()).future;
    },
  );

  Future<void> pumpApp(WidgetTester tester, GoRouter config) async {
    addTearDown(config.dispose);
    await tester.pumpWidget(BrandApp(routerConfig: config));
    if (ready == null) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('opens on home with the two tabs from the mockups', (
    tester,
  ) async {
    prepare();
    await pumpApp(tester, router());

    expect(find.text('home-body'), findsOneWidget);
    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(2));
  });

  testWidgets('the settings tab opens and home keeps its place', (
    tester,
  ) async {
    prepare();
    await pumpApp(tester, router());

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('settings-body'), findsOneWidget);

    await tester.tap(find.text('Главная'));
    await tester.pumpAndSettle();
    expect(find.text('home-body'), findsOneWidget);
  });

  for (final path in [
    '/connect/servers-import',
    '/servers',
    '/settings/backup',
    '/setup',
    '/splash',
  ]) {
    testWidgets('upstream route $path leads home', (tester) async {
      prepare();
      final config = router();
      await pumpApp(tester, config);

      config.go(path);
      await tester.pumpAndSettle();

      expect(find.text('home-body'), findsOneWidget);
      expect(config.state.uri.path, BrandRoutes.home);
    });
  }

  testWidgets('a cold link waits for the services and opens once', (
    tester,
  ) async {
    prepare();
    ready = Completer();
    links.add(_first);

    await pumpApp(tester, router());
    expect(opened, isEmpty);

    ready!.complete();
    await tester.pumpAndSettle();
    expect(opened, [_first]);

    finishLink.complete();
    await tester.pumpAndSettle();
    expect(opened, [_first]);
  });

  testWidgets('links queue one at a time', (tester) async {
    prepare();
    await pumpApp(tester, router());

    links.add(_first);
    await tester.pumpAndSettle();
    links.add(_second);
    await tester.pumpAndSettle();
    expect(opened, [_first]);

    finishLink.complete();
    await tester.pumpAndSettle();
    expect(opened, [_first, _second]);
    finishLink.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a link waits while a dialog is open', (tester) async {
    prepare();
    await pumpApp(tester, router());
    final context = tester.element(find.text('home-body'));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const Text('dialog-body'),
      ),
    );
    await tester.pumpAndSettle();

    links.add(_first);
    await tester.pumpAndSettle();
    expect(opened, isEmpty);

    Navigator.of(
      tester.element(find.text('dialog-body')),
      rootNavigator: true,
    ).pop();
    await tester.pumpAndSettle();
    expect(opened, [_first]);
    finishLink.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed start offers a retry', (tester) async {
    prepare();
    var attempts = 0;
    final config = createBrandRouter(
      home: const Text('home-body'),
      shareService: share,
      initializeServices: (_) async {
        if (++attempts == 1) throw StateError('no storage');
      },
    );
    await pumpApp(tester, config);

    expect(find.text('home-body'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('service-initialization-retry')),
    );
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('home-body'), findsOneWidget);
  });
}
