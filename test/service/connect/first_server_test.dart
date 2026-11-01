import 'dart:async';
import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/first_server.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/ping/batch.dart';

ResolvedProfile _group(List<String> servers) => ResolvedProfile(
  id: 1,
  sourceId: 1,
  name: 'AUTO',
  config: {
    'outbounds': [
      for (final tag in servers) {'tag': tag, 'protocol': 'vless'},
      {'tag': 'direct', 'protocol': 'freedom'},
      {'tag': 'block', 'protocol': 'blackhole'},
    ],
    'routing': {
      'balancers': [
        {
          'tag': 'auto',
          'selector': servers,
          'strategy': {'type': 'leastLoad'},
        },
      ],
      'rules': [
        {
          'outboundTag': 'direct',
          'domain': ['domain:example.ru'],
        },
        {'network': 'tcp,udp', 'balancerTag': 'auto'},
      ],
    },
  },
);

List<String> _tags(ResolvedProfile profile) => [
  for (final outbound in profile.config['outbounds'] as List)
    (outbound as Map<String, dynamic>)['tag'] as String,
];

String _tagOf(String outboundJson) {
  final config = jsonDecode(outboundJson) as Map<String, dynamic>;
  return ((config['outbounds'] as List).single as Map)['tag'] as String;
}

/// Answers the check from [delays]: a server not listed stays silent.
MeasureServers _answering(Map<String, int> delays) =>
    (outbounds, {required timeoutSeconds}) async => [
      for (final outbound in outbounds)
        delays[_tagOf(outbound)] == null
            ? PingBatchResult.failed()
            : PingBatchResult(true, delays[_tagOf(outbound)]!, ''),
    ];

/// The servers a check of [profile] measures.
Future<Set<String>> _checked(ResolvedProfile profile) async {
  final measured = <String>{};
  await FirstServerPicker(
    measure: (outbounds, {required timeoutSeconds}) async {
      measured.addAll(outbounds.map(_tagOf));
      return [for (final _ in outbounds) PingBatchResult.failed()];
    },
  ).pick(profile);
  return measured;
}

ResolvedProfile _graph(Map<String, dynamic> config) =>
    ResolvedProfile(id: 1, sourceId: 1, name: 'AUTO', config: config);

Map<String, dynamic> _server(String tag) => {'tag': tag, 'protocol': 'vless'};

void main() {
  test('the fastest server that answers leads the group', () async {
    final picked = await FirstServerPicker(
      measure: _answering({'slow': 900, 'fast': 300}),
    ).pick(_group(['dead', 'slow', 'fast']));

    expect(_tags(picked), ['fast', 'dead', 'slow', 'direct', 'block']);
  });

  test('all servers are measured in one batch', () async {
    final batches = <int>[];
    await FirstServerPicker(
      measure: (outbounds, {required timeoutSeconds}) async {
        batches.add(outbounds.length);
        return [for (final _ in outbounds) PingBatchResult.failed()];
      },
    ).pick(_group(['a', 'b', 'c']));

    expect(batches, [3]);
  });

  test('the panel order stays when no server answers', () async {
    final picked = await FirstServerPicker(measure: _answering({}))
        .pick(_group(['dead', 'silent']));

    expect(_tags(picked), ['dead', 'silent', 'direct', 'block']);
  });

  test('a failed check leaves the panel order and the connection', () async {
    final picked = await FirstServerPicker(
      measure: (_, {required timeoutSeconds}) =>
          Future.error(StateError('native failure')),
    ).pick(_group(['a', 'b']));

    expect(_tags(picked), ['a', 'b', 'direct', 'block']);
  });

  test('the panel order stays when the check runs out of time', () {
    fakeAsync((time) {
      final picker = FirstServerPicker(
        measure: (_, {required timeoutSeconds}) =>
            Completer<List<PingBatchResult>>().future,
      );
      List<String>? tags;
      unawaited(
        picker.pick(_group(['a', 'b'])).then((value) => tags = _tags(value)),
      );

      time.elapse(const Duration(milliseconds: 2999));
      expect(tags, isNull);
      time.elapse(const Duration(milliseconds: 1));
      expect(tags, ['a', 'b', 'direct', 'block']);
    });
  });

  test('cancelling the connection ends the check at once', () async {
    final cancelled = Completer<void>();
    final picker = FirstServerPicker(
      measure: (_, {required timeoutSeconds}) =>
          Completer<List<PingBatchResult>>().future,
    );

    final picking = picker.pick(
      _group(['a', 'b']),
      cancelled: cancelled.future,
    );
    cancelled.complete();

    expect(_tags(await picking), ['a', 'b', 'direct', 'block']);
  });

  for (final mode in [TrafficMode.smart, TrafficMode.allVpn]) {
    test('the picked server stays first in the ${mode.name} session', () async {
      final picked = await FirstServerPicker(measure: _answering({'live': 100}))
          .pick(_group(['dead', 'live']));

      final compiled = ConnectionCompiler.compile(
        settings: ConnectionSettings(
          trafficMode: mode,
          selection: const ServerSelection.server(1),
        ),
        entries: const [],
        profile: picked,
        regions: const RegionCatalog.empty(),
        options: RuntimeOptions(
          platform: ConnectionPlatform.android,
          sessionDirectory: '/unused-session',
          metricsPort: 18186,
          socksPort: 18187,
        ),
      ).config;

      expect((compiled['outbounds'] as List).first['tag'], 'live');
    });
  }

  group('servers worth checking', () {
    test('come from the balancer of the last rule', () async {
      final profile = _graph({
        'outbounds': [
          _server('lte-1'),
          _server('lte-2'),
          _server('a'),
          _server('b'),
        ],
        'routing': {
          'balancers': [
            {
              'tag': 'lte',
              'selector': ['lte-1', 'lte-2'],
              'strategy': {'type': 'leastLoad'},
            },
            {
              'tag': 'main',
              'selector': ['a', 'b'],
              'strategy': {'type': 'leastPing'},
            },
          ],
          'rules': [
            {
              'inboundTag': ['lte-in'],
              'balancerTag': 'lte',
            },
            {'network': 'tcp,udp', 'balancerTag': 'main'},
          ],
        },
      });

      expect(await _checked(profile), {'a', 'b'});
    });

    test('match the selector by tag prefix, as the core does', () async {
      final profile = _graph({
        'outbounds': [_server('de-1'), _server('nl-1'), _server('de-2')],
        'routing': {
          'balancers': [
            {
              'tag': 'auto',
              'selector': ['de-'],
              'strategy': {'type': 'leastLoad'},
            },
          ],
          'rules': [
            {'balancerTag': 'auto'},
          ],
        },
      });

      expect(await _checked(profile), {'de-1', 'de-2'});
    });

    test('leave out what a selector names but cannot be pinged', () async {
      final profile = _graph({
        'outbounds': [
          _server('a'),
          _server('b'),
          {
            ..._server('chained'),
            'proxySettings': {'tag': 'a'},
          },
          {
            ..._server('dialed'),
            'streamSettings': {
              'sockopt': {'dialerProxy': 'a'},
            },
          },
          {'tag': 'loop', 'protocol': 'loopback'},
          {'tag': 'off', 'protocol': 'freedom'},
        ],
        'routing': {
          'balancers': [
            {
              'tag': 'auto',
              'selector': ['a', 'b', 'chained', 'dialed', 'loop', 'off'],
              'strategy': {'type': 'leastLoad'},
            },
          ],
          'rules': [
            {'balancerTag': 'auto'},
          ],
        },
      });

      expect(await _checked(profile), {'a', 'b'});
    });

    test('are at most five', () async {
      final checked = await _checked(
        _group(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']),
      );

      expect(checked, hasLength(5));
    });

    test('do not exist in a group sent to one server', () async {
      final profile = _graph({
        'outbounds': [_server('a'), _server('b')],
        'routing': {
          'rules': [
            {'network': 'tcp,udp', 'outboundTag': 'a'},
          ],
        },
      });

      expect(await _checked(profile), isEmpty);
    });

    test(
      'do not exist when the last rule is narrower than all traffic',
      () async {
        final profile = _graph({
          'outbounds': [_server('a'), _server('b')],
          'routing': {
            'balancers': [
              {
                'tag': 'auto',
                'selector': ['a', 'b'],
                'strategy': {'type': 'leastLoad'},
              },
            ],
            'rules': [
              {
                'domain': ['domain:example.org'],
                'balancerTag': 'auto',
              },
            ],
          },
        });

        expect(await _checked(profile), isEmpty);
      },
    );

    test('do not exist when the last rule leaves out a network', () async {
      final profile = _graph({
        'outbounds': [_server('a'), _server('b')],
        'routing': {
          'balancers': [
            {
              'tag': 'auto',
              'selector': ['a', 'b'],
              'strategy': {'type': 'leastLoad'},
            },
          ],
          'rules': [
            {'network': 'tcp', 'balancerTag': 'auto'},
          ],
        },
      });

      expect(await _checked(profile), isEmpty);
    });

    test('do not exist when the balancer needs no measurements', () async {
      final profile = _graph({
        'outbounds': [_server('a'), _server('b')],
        'routing': {
          'balancers': [
            {
              'tag': 'auto',
              'selector': ['a', 'b'],
              'strategy': {'type': 'roundRobin'},
            },
          ],
          'rules': [
            {'balancerTag': 'auto'},
          ],
        },
      });

      expect(await _checked(profile), isEmpty);
    });

    test('do not exist when one server is all a balancer has', () async {
      expect(await _checked(_group(['only'])), isEmpty);
    });

    test(
      'do not exist in a malformed graph, left for Core to reject',
      () async {
        expect(await _checked(_graph({'outbounds': 'broken'})), isEmpty);
        expect(
          await _checked(_graph({'outbounds': [], 'routing': 'broken'})),
          isEmpty,
        );
      },
    );
  });
}
