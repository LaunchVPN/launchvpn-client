import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';

const _catchAll = {
  'type': 'field',
  'network': 'tcp,udp',
  'balancerTag': 'pool',
};
const _quicBlock = {
  'type': 'field',
  'network': 'udp',
  'port': '443',
  'outboundTag': 'block',
};
const _sites = {
  'type': 'field',
  'domain': ['gosuslugi.ru', 'domain:1tv.ru'],
  'outboundTag': 'direct',
};

/// Shaped like one group of the panel's xray-json. Its first outbound is a
/// server, so traffic without a matching rule never leaves directly.
Map<String, dynamic> _panelGraph(
  List<Map<String, dynamic>> rules, {
  List<Map<String, dynamic>> extraOutbounds = const [],
}) => {
  'inbounds': [
    {'tag': 'socks', 'protocol': 'socks', 'port': 10808},
  ],
  'outbounds': [
    {
      'tag': 'edge',
      'protocol': 'vless',
      'settings': {'address': 'edge.example', 'port': 443},
    },
    {'tag': 'direct', 'protocol': 'freedom'},
    {'tag': 'block', 'protocol': 'blackhole'},
    ...extraOutbounds,
  ],
  'routing': {
    'domainStrategy': 'IPIfNonMatch',
    'balancers': [
      {
        'tag': 'pool',
        'selector': ['edge'],
      },
    ],
    'rules': rules,
  },
};

Map<String, dynamic> _compile(
  TrafficMode preset,
  List<Map<String, dynamic>> rules, {
  List<Map<String, dynamic>> extraOutbounds = const [],
}) => ConnectionCompiler.compile(
  settings: ConnectionSettings(trafficMode: preset),
  entries: const [],
  profile: ResolvedProfile(
    id: 1,
    sourceId: 1,
    name: 'AUTO',
    config: _panelGraph(rules, extraOutbounds: extraOutbounds),
  ),
  regions: const RegionCatalog.empty(),
  options: RuntimeOptions(
    platform: ConnectionPlatform.android,
    sessionDirectory: '/unused-session',
    metricsPort: 18186,
    socksPort: 18187,
  ),
).config;

/// The panel's own rules, without the DNS rules the app adds around them.
List<Map<String, dynamic>> _panelRules(Map<String, dynamic> config) => [
  for (final rule in config['routing']['rules'] as List)
    if (rule['port'] != '53' && rule['inboundTag'] == null)
      rule as Map<String, dynamic>,
];

void main() {
  test('Smart keeps the panel rules as delivered', () {
    expect(_panelRules(_compile(TrafficMode.smart, [_sites, _catchAll])), [
      _sites,
      _catchAll,
    ]);
  });

  test('Everything through VPN removes rules that go direct', () {
    expect(
      _panelRules(
        _compile(TrafficMode.allVpn, [_quicBlock, _sites, _catchAll]),
      ),
      [_quicBlock, _catchAll],
    );
  });

  test('Everything through VPN keeps the local network direct', () {
    const privateRanges = {
      'type': 'field',
      'ip': ['10.0.0.0/8', '192.168.0.0/16', 'fc00::/7', '0000::/127'],
      'outboundTag': 'direct',
    };
    const oneHomeSubnet = {
      'type': 'field',
      'ip': ['192.168.1.0/24', 'geoip:private'],
      'outboundTag': 'direct',
    };
    const localAndInternet = {
      'type': 'field',
      'ip': ['172.16.0.0/12', '8.8.8.0/24'],
      'outboundTag': 'direct',
    };

    expect(
      _panelRules(
        _compile(TrafficMode.allVpn, [
          privateRanges,
          oneHomeSubnet,
          localAndInternet,
          _catchAll,
        ]),
      ),
      [
        privateRanges,
        oneHomeSubnet,
        {
          ...localAndInternet,
          'ip': ['172.16.0.0/12'],
        },
        _catchAll,
      ],
    );
  });

  test(
    'Everything through VPN blocks torrents instead of sending them direct',
    () {
      const trackers = {
        'type': 'field',
        'domain': ['router.bittorrent.com', 'tracker.example'],
        'outboundTag': 'direct',
      };
      const torrents = {
        'type': 'field',
        'protocol': ['bittorrent'],
        'outboundTag': 'direct',
      };
      const torrentsAndWeb = {
        'type': 'field',
        'protocol': ['bittorrent', 'tls'],
        'outboundTag': 'direct',
      };
      const similarHost = {
        'type': 'field',
        'domain': ['xrouter.bittorrent.com'],
        'outboundTag': 'direct',
      };

      expect(
        _panelRules(
          _compile(TrafficMode.allVpn, [
            trackers,
            torrents,
            torrentsAndWeb,
            similarHost,
            _catchAll,
          ]),
        ),
        [
          {...trackers, 'outboundTag': 'block'},
          {...torrents, 'outboundTag': 'block'},
          {...torrents, 'outboundTag': 'block'},
          _catchAll,
        ],
      );
    },
  );

  test('a direct outbound without a tag does not remove proxy rules', () {
    expect(
      _panelRules(
        _compile(
          TrafficMode.allVpn,
          [_catchAll],
          extraOutbounds: [
            {'protocol': 'freedom'},
          ],
        ),
      ),
      [_catchAll],
    );
  });

  group('DNS', () {
    List<Map<String, dynamic>> outbounds(Map<String, dynamic> config) => [
      for (final outbound in config['outbounds'] as List)
        outbound as Map<String, dynamic>,
    ];

    /// The protocol of the outbound that carries queries the core does not
    /// answer itself, such as HTTPS records.
    String forwardedThrough(Map<String, dynamic> config) {
      final all = outbounds(config);
      final dns = all.firstWhere((value) => value['protocol'] == 'dns');
      final tag = dns['streamSettings']['sockopt']['dialerProxy'];
      return all.firstWhere((value) => value['tag'] == tag)['protocol']
          as String;
    }

    /// The protocol of the outbound that a rule gives to the core's own lookups.
    String? lookupsGoThrough(Map<String, dynamic> config) {
      final tag = (config['dns']['servers'] as List).first['tag'];
      final rule = (config['routing']['rules'] as List)
          .where(
            (value) => (value['inboundTag'] as List?)?.contains(tag) == true,
          )
          .firstOrNull;
      if (rule == null) return null;
      return outbounds(config).firstWhere(
            (value) => value['tag'] == rule['outboundTag'],
          )['protocol']
          as String;
    }

    test('Smart resolves names directly', () {
      final config = _compile(TrafficMode.smart, [_catchAll]);

      expect(lookupsGoThrough(config), 'freedom');
      expect(forwardedThrough(config), 'freedom');
    });

    test(
      'Everything through VPN sends all queries through the graph rules',
      () {
        final config = _compile(TrafficMode.allVpn, [_catchAll]);

        expect(lookupsGoThrough(config), isNull);
        expect(forwardedThrough(config), 'loopback');
      },
    );
  });
}
