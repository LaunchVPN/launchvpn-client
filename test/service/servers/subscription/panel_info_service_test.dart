import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/panel_info.dart';
import 'package:onexray/service/servers/subscription/reader.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  const input = SubscriptionInput(
    name: 'Panel',
    url: 'https://example.com/sub',
  );
  const firstInfo = SubscriptionPanelInfo(
    title: 'LaunchVPN',
    supportUrl: 'https://example.com/help',
    updateIntervalHours: 12,
  );

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
  });

  SubscriptionLoadResult loaded(SubscriptionPanelInfo? panelInfo) =>
      SubscriptionLoadResult(
        status: SubscriptionUpdateResult.success,
        rows: [
          outboundCompanion({'tag': 'Node', 'protocol': 'socks'}),
        ],
        panelInfo: panelInfo,
      );

  SubscriptionService service(
    Future<SubscriptionLoadResult> Function(SubscriptionInput) load,
  ) => SubscriptionService.forTesting(
    database: database,
    loadRows: load,
    schedulePing: (_) {},
    readReferences: () => const SubscriptionNodeReferences(),
  );

  Future<SubscriptionData> stored(int id) async =>
      (await database.subscriptionDao.searchRow(id))!;

  void expectNoInfo(SubscriptionData source) {
    expect(source.profileTitle, isNull);
    expect(source.supportUrl, isNull);
    expect(source.updateIntervalHours, isNull);
  }

  test('every download replaces all three values from its headers', () async {
    var headers = <String, List<String>>{
      'profile-title': ['base64:TGF1bmNoVlBO'],
      'support-url': ['https://example.com/help'],
      'profile-update-interval': ['12'],
    };
    final client = Dio()
      ..httpClientAdapter = _Response(
        () => ResponseBody.fromString(
          jsonEncode({
            'remarks': 'Saved',
            'outbounds': [
              {'tag': 'proxy', 'protocol': 'socks'},
            ],
          }),
          200,
          headers: headers,
        ),
      );
    addTearDown(client.close);
    final subject = SubscriptionService.forTesting(
      database: database,
      client: NetClient.forTesting(client),
      configurationReader: SubscriptionConfigurationReader(
        decode: (text, {ageSecretKey}) async => text,
        validate: (_) async => '',
        readNodes: (_) async => throw StateError('Not an ordinary response'),
        withFiles: (action) => action(),
      ),
      schedulePing: (_) {},
      readReferences: () => const SubscriptionNodeReferences(),
    );

    final inserted = await subject.insertSubscription(
      const SubscriptionInput(
        name: 'Panel',
        url: 'https://example.com/sub',
        panel: SubscriptionPanel.remnawave,
      ),
    );
    final first = await stored(inserted.subId);
    expect(first.profileTitle, 'LaunchVPN');
    expect(first.supportUrl, 'https://example.com/help');
    expect(first.updateIntervalHours, 12);

    headers = {
      'profile-update-interval': ['6'],
    };
    expect((await subject.refreshSubscriptionResult(first)).success, isTrue);
    final second = await stored(first.id);
    expect(second.profileTitle, isNull);
    expect(second.supportUrl, isNull);
    expect(second.updateIntervalHours, 6);
  });

  test('a failed download keeps the saved values', () async {
    var response = loaded(firstInfo);
    final subject = service((_) async => response);
    final inserted = await subject.insertSubscription(input);
    final source = await stored(inserted.subId);

    response = const SubscriptionLoadResult(
      status: SubscriptionUpdateResult.downloadFailed,
      panelInfo: SubscriptionPanelInfo(updateIntervalHours: 1),
    );
    expect((await subject.refreshSubscriptionResult(source)).success, isFalse);

    expect(await stored(source.id), source);
  });

  test('a new request source clears the values; a rename keeps them', () async {
    final subject = service((_) async => loaded(firstInfo));
    final inserted = await subject.insertSubscription(input);

    await subject.saveSubscriptionInput(
      inserted.subId,
      const SubscriptionInput(name: 'Renamed', url: 'https://example.com/sub'),
    );
    expect((await stored(inserted.subId)).updateIntervalHours, 12);

    await subject.saveSubscriptionInput(
      inserted.subId,
      const SubscriptionInput(name: 'Renamed', url: 'https://example.com/new'),
    );
    expectNoInfo(await stored(inserted.subId));
  });

  group('automatic updates', () {
    final settings = AutoUpdateState()
      ..subscriptionEnabled = true
      ..subscriptionInterval = AutoUpdateInterval.threeDays;

    Future<void> addSource(String name, Duration age, int? hours) async {
      await database.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: name,
          url: 'https://example.com/$name',
          timestamp: DateTime.now().subtract(age),
          updateIntervalHours: Value(hours),
        ),
      );
    }

    test('the panel interval decides when a source is due', () async {
      await addSource('due', const Duration(hours: 13), 12);
      await addSource('fresh', const Duration(hours: 11), 12);
      await addSource('hourly', const Duration(minutes: 61), 1);
      await addSource('slow', const Duration(days: 4), 240);
      final downloads = <String>[];
      final subject = service((source) async {
        downloads.add(source.name);
        return loaded(null);
      });

      await subject.refreshOutdatedSubscription(autoUpdateState: settings);

      expect(downloads, unorderedEquals(['due', 'hourly']));
    });

    test('an hourly check does not miss an hourly interval', () async {
      await addSource('checked at the hour', const Duration(minutes: 59), 1);
      await addSource('too early', const Duration(minutes: 54), 1);
      await addSource('endless', const Duration(days: 4), 9223372036854775807);
      final downloads = <String>[];
      final subject = service((source) async {
        downloads.add(source.name);
        return loaded(null);
      });

      await subject.refreshOutdatedSubscription(autoUpdateState: settings);

      expect(downloads, ['checked at the hour']);
    });

    test('without a panel interval the app setting applies', () async {
      await addSource('due', const Duration(hours: 73), null);
      await addSource('fresh', const Duration(hours: 71), null);
      final downloads = <String>[];
      final subject = service((source) async {
        downloads.add(source.name);
        return loaded(null);
      });

      await subject.refreshOutdatedSubscription(autoUpdateState: settings);

      expect(downloads, ['due']);
    });

    test('a refresh restarts the panel interval', () async {
      await addSource('source', const Duration(hours: 2), 1);
      final downloads = <String>[];
      final subject = service((source) async {
        downloads.add(source.name);
        return loaded(const SubscriptionPanelInfo(updateIntervalHours: 1));
      });

      await subject.refreshOutdatedSubscription(autoUpdateState: settings);
      await subject.refreshOutdatedSubscription(autoUpdateState: settings);

      expect(downloads, ['source']);
    });
  });
}

class _Response implements HttpClientAdapter {
  _Response(this.respond);

  final ResponseBody Function() respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond();

  @override
  void close({bool force = false}) {}
}
