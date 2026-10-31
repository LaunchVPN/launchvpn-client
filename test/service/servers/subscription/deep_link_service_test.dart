import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

const _oldUrl = 'https://sub.launch.tel/old';
const _newUrl = 'https://sub.launch.tel/new';

void main() {
  late AppDatabase db;
  late List<SubscriptionInput> downloads;

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    downloads = [];
  });

  SubscriptionService subscriptions({
    SubscriptionUpdateResult status = SubscriptionUpdateResult.success,
  }) => SubscriptionService.forTesting(
    database: db,
    schedulePing: (_) {},
    readReferences: () => const SubscriptionNodeReferences(),
    loadRows: (input) async {
      downloads.add(input);
      return SubscriptionLoadResult(
        status: status,
        mode: SubscriptionMode.providerManaged,
        rows: [_profileRow('From ${input.url}')],
      );
    },
  );

  Future<ConnectionCoordinator> coordinator({
    HostConnection host = const HostConnection(VpnStatus.disconnected),
    List<String>? calls,
  }) async {
    var current = host;
    final value = ConnectionCoordinator(
      database: db,
      readRuntime: () async => host.runtime,
      inspect: (_, {observedStatus}) async => current,
      start: (runtime) async {
        calls?.add('start');
        return current = HostConnection(VpnStatus.connected, runtime: runtime);
      },
      stop: () async {
        calls?.add('stop');
        return current = const HostConnection(VpnStatus.disconnected);
      },
    );
    addTearDown(value.dispose);
    await value.initialize(observe: false, registerReferences: false);
    return value;
  }

  Future<SubscriptionLinkService> service({
    SubscriptionUpdateResult status = SubscriptionUpdateResult.success,
    ConnectionCoordinator? connection,
  }) async {
    final source = subscriptions(status: status);
    return SubscriptionLinkService(
      database: db,
      subscriptions: source,
      servers: ServerAssetService(
        database: db,
        coordinator: connection ?? await coordinator(),
        subscriptions: source,
      ),
    );
  }

  Future<CoreConfigData> existing(String url) async {
    final subId = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Existing',
        url: url,
        timestamp: DateTime(2026),
        mode: Value(SubscriptionMode.providerManaged.name),
      ),
    );
    final id = await db.coreConfigDao.insertAssetRow(
      _profileRow('Existing').copyWith(subId: Value(subId)),
    );
    return (await db.coreConfigDao.searchRow(id))!;
  }

  Future<List<String>> subscriptionUrls() async =>
      (await db.subscriptionDao.allRows).map((row) => row.url).toList();

  test('the first subscription is added as a Remnawave source', () async {
    final subject = await service();
    final link = _link(_newUrl);

    expect(await subject.replacesAnother(link), isFalse);
    final result = await subject.apply(link);

    expect(result.success, isTrue);
    expect(await subscriptionUrls(), [_newUrl]);
    expect(downloads.single.panel, SubscriptionPanel.remnawave);
  });

  test(
    'a different subscription replaces the old one and its servers',
    () async {
      final old = await existing(_oldUrl);
      final subject = await service();
      final link = _link(_newUrl);

      expect(await subject.replacesAnother(link), isTrue);
      final result = await subject.apply(link);

      expect(result.success, isTrue);
      expect(await subscriptionUrls(), [_newUrl]);
      expect(await db.coreConfigDao.searchRow(old.id), isNull);
    },
  );

  test('the same subscription is refreshed, not added again', () async {
    final old = await existing(_newUrl);
    final subject = await service();
    final link = _link(_newUrl);

    expect(await subject.replacesAnother(link), isFalse);
    final result = await subject.apply(link);

    expect(result.success, isTrue);
    expect(result.subId, old.subId);
    expect(await subscriptionUrls(), [_newUrl]);
    expect(downloads, hasLength(1));
  });

  test(
    'a failed download keeps the old subscription and its servers',
    () async {
      final old = await existing(_oldUrl);
      final subject = await service(
        status: SubscriptionUpdateResult.hwidLimitReached,
      );

      final result = await subject.apply(_link(_newUrl));

      expect(result.status, SubscriptionUpdateResult.hwidLimitReached);
      expect(await subscriptionUrls(), [_oldUrl]);
      expect(await db.coreConfigDao.searchRow(old.id), old);
    },
  );

  test('a selected old server falls back to the automatic selection', () async {
    final old = await existing(_oldUrl);
    await db.connectionConfigDao.commit(
      configurationJson: ConnectionConfiguration(
        connection: ConnectionSettings(
          selection: ServerSelection.server(old.id),
        ),
      ).encode(),
    );
    final connection = await coordinator();
    final subject = await service(connection: connection);

    await subject.apply(_link(_newUrl));

    expect(
      (await connection.configuration).connection.selection.kind,
      SelectionKind.automatic,
    );
  });

  test(
    'a VPN running on the old subscription reconnects to the new one',
    () async {
      final old = await existing(_oldUrl);
      final configuration = ConnectionConfiguration();
      await db.connectionConfigDao.commit(
        configurationJson: configuration.encode(),
      );
      final calls = <String>[];
      final connection = await coordinator(
        host: HostConnection(
          VpnStatus.connected,
          runtime: _runtime(configuration, old),
        ),
        calls: calls,
      );
      final source = subscriptions();
      final subject = SubscriptionLinkService(
        database: db,
        subscriptions: source,
        servers: ServerAssetService(
          database: db,
          coordinator: connection,
          subscriptions: source,
          prepare: (next, _, _, _) async {
            final replacement = (await db.coreConfigDao.allActiveServerRows())
                .singleWhere((row) => row.subId != old.subId);
            return _runtime(next, replacement);
          },
        ),
      );

      final result = await subject.apply(_link(_newUrl));

      expect(result.success, isTrue);
      expect(calls, ['stop', 'start']);
      expect(connection.state.value.phase, ConnectionPhase.connected);
      expect(connection.state.value.runtime?.profile?.id, isNot(old.id));
      expect(await subscriptionUrls(), [_newUrl]);
    },
  );
}

SubscriptionDeepLink _link(String url) => SubscriptionDeepLink.parse(
  Uri(
    scheme: 'launchvpn',
    host: 'sub',
    path: '/add',
    queryParameters: {'url': url},
  ),
)!;

CoreConfigCompanion _profileRow(String name) => CoreConfigCompanion.insert(
  name: name,
  type: CoreConfigType.Remnawave.name,
  tags: '',
  subId: DBConstants.defaultId,
  delay: PingDelayConstants.unknown,
  data: Value(base64Encode(utf8.encode(jsonEncode(_profile)))),
);

ConnectionRuntime _runtime(
  ConnectionConfiguration configuration,
  CoreConfigData row,
) {
  final profile = ResolvedProfile.fromRow(row);
  final text = jsonEncode(profile.config);
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: CompiledConnection(
      xrayJson: text,
      entries: const [],
      finalExit: null,
      nodeTags: const {},
      profile: profile,
    ),
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(
      configuration.policy.toTun(ConnectionPlatform.android),
      null,
      '18003',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(text).toJson(),
        ).toJson(),
      ),
    ),
  );
}

const _profile = <String, dynamic>{
  'remarks': 'Provider',
  'inbounds': [
    {'tag': 'provider-socks', 'protocol': 'socks', 'port': 1080},
  ],
  'outbounds': [
    {'tag': 'proxy', 'protocol': 'socks'},
  ],
  'routing': {'rules': []},
};
