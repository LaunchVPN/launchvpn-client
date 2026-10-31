import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/subscription_link_flow.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/servers/subscription/failure.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _oldUrl = 'https://sub.launch.tel/old';
const _newUrl = 'https://sub.launch.tel/new';
final _uri = Uri.parse('launchvpn://sub/add?url=$_newUrl');

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late Completer<void> download;
  late SubscriptionUpdateResult status;
  late int downloads;

  setUp(() async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    download = Completer<void>()..complete();
    status = SubscriptionUpdateResult.success;
    downloads = 0;
    coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => null,
      inspect: (_, {observedStatus}) async =>
          const HostConnection(VpnStatus.disconnected),
      start: (_) async => throw StateError('No implicit start'),
      stop: () async => throw StateError('No implicit stop'),
    );
    addTearDown(coordinator.dispose);
    await coordinator.initialize(observe: false, registerReferences: false);
  });

  SubscriptionLinkService service() {
    final subscriptions = SubscriptionService.forTesting(
      database: db,
      schedulePing: (_) {},
      readReferences: () => const SubscriptionNodeReferences(),
      loadRows: (input) async {
        downloads++;
        await download.future;
        return SubscriptionLoadResult(
          status: status,
          mode: SubscriptionMode.providerManaged,
          rows: [_profileRow()],
        );
      },
    );
    return SubscriptionLinkService(
      database: db,
      subscriptions: subscriptions,
      servers: ServerAssetService(
        database: db,
        coordinator: coordinator,
        subscriptions: subscriptions,
      ),
    );
  }

  Future<void> existing() => db.subscriptionDao.insertRow(
    SubscriptionCompanion.insert(
      name: 'Existing',
      url: _oldUrl,
      timestamp: DateTime(2026),
    ),
  );

  Future<List<String>> urls() async =>
      (await db.subscriptionDao.allRows).map((row) => row.url).toList();

  /// Starts the flow from a ready screen and leaves it running.
  Future<void> open(WidgetTester tester, Uri uri) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ShadTheme(
          data: ShadThemeData(colorScheme: const ShadBlueColorScheme.light()),
          child: ShadToaster(child: child ?? const SizedBox.shrink()),
        ),
        home: const Scaffold(body: Text('home')),
      ),
    );
    unawaited(
      openSubscriptionLink(
        tester.element(find.text('home')),
        uri,
        service: service(),
      ),
    );
    await settle(tester);
  }

  testWidgets('a foreign link only explains the problem', (tester) async {
    await tester.runAsync(existing);

    await open(
      tester,
      Uri.parse('launchvpn://sub/add?url=https://provider.example/token'),
    );

    expect(find.text("This link doesn't work with LaunchVPN"), findsOneWidget);
    expect(downloads, 0);
    expect(await tester.runAsync(urls), [_oldUrl]);
  });

  testWidgets(
    'the first subscription needs no confirmation and shows progress',
    (tester) async {
      download = Completer<void>();

      await open(tester, _uri);
      expect(find.text('Replace subscription?'), findsNothing);
      expect(find.text('Adding subscription…'), findsOneWidget);

      download.complete();
      await settle(tester);

      expect(find.text('Adding subscription…'), findsNothing);
      expect(find.text('Subscription added'), findsOneWidget);
      expect(await tester.runAsync(urls), [_newUrl]);
    },
  );

  testWidgets('finishing closes the progress, not a dialog opened above it', (
    tester,
  ) async {
    download = Completer<void>();
    await open(tester, _uri);
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('home')),
        useRootNavigator: false,
        builder: (_) => const AlertDialog(content: Text('other dialog')),
      ),
    );
    await settle(tester);

    download.complete();
    await settle(tester);

    expect(find.text('other dialog'), findsOneWidget);
    expect(find.text('Adding subscription…'), findsNothing);
  });

  testWidgets('a database failure says so instead of dropping the link', (
    tester,
  ) async {
    await tester.runAsync(
      () => db.customStatement('DROP TABLE ${db.subscription.actualTableName}'),
    );

    await open(tester, _uri);

    expect(find.byType(ShadToast), findsOneWidget);
    expect(downloads, 0);
  });

  testWidgets('declining the replacement downloads nothing', (tester) async {
    await tester.runAsync(existing);

    await open(tester, _uri);
    expect(find.text('Replace subscription?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(downloads, 0);
    expect(await tester.runAsync(urls), [_oldUrl]);
  });

  testWidgets('confirming the replacement leaves only the new subscription', (
    tester,
  ) async {
    await tester.runAsync(existing);

    await open(tester, _uri);
    await tester.tap(find.text('Replace'));
    await settle(tester);

    expect(find.text('Subscription added'), findsOneWidget);
    expect(await tester.runAsync(urls), [_newUrl]);
  });

  testWidgets('a failed download says why and keeps the old subscription', (
    tester,
  ) async {
    await tester.runAsync(existing);
    status = SubscriptionUpdateResult.downloadFailed;

    await open(tester, _uri);
    await tester.tap(find.text('Replace'));
    await settle(tester);

    final l10n = AppLocalizations.of(tester.element(find.text('home')))!;
    expect(
      find.text(
        subscriptionFailureMessage(
          l10n,
          SubscriptionUpdateResult.downloadFailed,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Subscription added'), findsNothing);
    expect(await tester.runAsync(urls), [_oldUrl]);
  });
}

/// Lets the in-memory database finish between frames.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
}

CoreConfigCompanion _profileRow() => CoreConfigCompanion.insert(
  name: 'Provider',
  type: CoreConfigType.Remnawave.name,
  tags: '',
  subId: DBConstants.defaultId,
  delay: PingDelayConstants.unknown,
  data: Value(
    base64Encode(
      utf8.encode(
        jsonEncode({
          'remarks': 'Provider',
          'outbounds': [
            {'tag': 'proxy', 'protocol': 'socks'},
          ],
        }),
      ),
    ),
  ),
);
