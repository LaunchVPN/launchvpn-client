import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/locations.dart';

void main() {
  LocationList list(List<CoreConfigData> rows) => LocationList.from(
    ServerCatalog(
      servers: rows,
      sources: [
        SubscriptionData(
          id: 1,
          name: 'LaunchVPN',
          url: 'https://sub.launch.tel/a',
          panel: 'remnawave',
          mode: SubscriptionMode.providerManaged.name,
          hwidEnabled: false,
          timestamp: DateTime(2026),
        ),
      ],
    ),
  );

  test('sorts panel rows into automatic groups and the rest, keeping the panel order', () {
    final locations = list([
      _row(1, '🇪🇺 AUTO | Самые быстрые'),
      _row(2, '🇷🇺 AUTO | Обход глушилок Способ 2'),
      _row(3, '🇷🇺 YouTube | Без рекламы'),
      _row(4, '🇩🇪 Германия'),
      _row(5, '🇺🇸  США'),
      _row(6, 'Запасной'),
    ]);

    expect(locations.automatic.map((item) => item.name), [
      'Самые быстрые',
      'Обход глушилок Способ 2',
    ]);
    expect(locations.others.map((item) => item.name), [
      'YouTube · Без рекламы',
      'Германия',
      'США',
      'Запасной',
    ]);
    expect(locations.others.map((item) => item.countryCode), [
      'RU',
      'DE',
      'US',
      null,
    ]);
    expect(locations.automatic.map((item) => item.bypass), [false, true]);
  });

  test(
    'shows a group kept by a running session only once, as its fresh row',
    () {
      final locations = list([
        _row(1, '🇪🇺 AUTO | Самые быстрые'),
        _row(2, '🇩🇪 Германия'),
        _row(10, '🇪🇺 AUTO | Самые быстрые'),
        _row(11, '🇩🇪 Германия'),
      ]);

      expect(locations.all.map((item) => item.id), [10, 11]);
    },
  );

  test('leaves out a row that cannot be read', () {
    final locations = list([
      _row(1, '🇩🇪 Германия', data: 'not base64'),
      _row(2, '🇵🇱 Польша'),
    ]);

    expect(locations.all.map((item) => item.name), ['Польша']);
  });

  test('finds the location of a stored selection, otherwise the first one', () {
    final locations = list([
      _row(1, '🇪🇺 AUTO | Самые быстрые'),
      _row(2, '🇩🇪 Германия'),
    ]);

    expect(locations.withId(2)?.name, 'Германия');
    expect(locations.withId(99), isNull);
    expect(locations.first?.name, 'Самые быстрые');
    expect(list(const []).first, isNull);
  });

  test('carries the last measured delay', () {
    final locations = list([
      _row(1, '🇩🇪 Германия', delay: 516),
      _row(2, '🇬🇧 Англия', delay: PingDelayConstants.timeout),
      _row(3, '🇵🇱 Польша'),
    ]);

    expect(locations.all.map((item) => item.delay), [
      516,
      PingDelayConstants.timeout,
      PingDelayConstants.unknown,
    ]);
  });
}

CoreConfigData _row(
  int id,
  String name, {
  String? data,
  int delay = PingDelayConstants.unknown,
}) => CoreConfigData(
  id: id,
  name: name,
  type: CoreConfigType.Remnawave.name,
  tags: '',
  favorite: false,
  subId: 1,
  delay: delay,
  manualSortOrder: 0,
  data:
      data ??
      base64Encode(
        utf8.encode(
          jsonEncode({
            'outbounds': [
              {'tag': 'proxy', 'protocol': 'vless'},
            ],
          }),
        ),
      ),
);
