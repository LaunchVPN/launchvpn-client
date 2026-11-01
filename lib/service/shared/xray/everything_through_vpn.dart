import 'dart:io';

import 'package:onexray/core/tools/json.dart';

/// The "Everything through VPN" preset on a complete provider graph: rules that
/// send internet traffic past the VPN are removed, so it reaches the graph's
/// own proxy rules instead. Local network destinations never reach the internet
/// and stay direct, as they do on iOS by default.
abstract final class EverythingThroughVpn {
  static const _dnsForwardTag = 'app-vpn-dns-forward';

  static const _torrentBootstrapHosts = {
    'router.bittorrent.com',
    'router.utorrent.com',
    'dht.transmissionbt.com',
  };

  static final _localRanges = [
    for (final range in const [
      '0.0.0.0/8',
      '10.0.0.0/8',
      '100.64.0.0/10',
      '127.0.0.0/8',
      '169.254.0.0/16',
      '172.16.0.0/12',
      '192.0.0.0/24',
      '192.0.2.0/24',
      '192.88.99.0/24',
      '192.168.0.0/16',
      '198.18.0.0/15',
      '198.51.100.0/24',
      '203.0.113.0/24',
      '224.0.0.0/3',
      '::/127',
      'fc00::/7',
      'fe80::/10',
      'ff00::/8',
    ])
      _Cidr.parse(range)!,
  ];

  static Map<String, dynamic> apply(Map<String, dynamic> source) {
    final config = JsonTool.copyMap(source);
    final outbounds = config['outbounds'];
    final routing = config['routing'];
    // Malformed containers stay as they are for Core validation.
    if (outbounds is! List ||
        routing is! Map<String, dynamic> ||
        routing['rules'] is! List) {
      return config;
    }
    final direct = _tagsOf(outbounds, 'freedom');
    final blackhole = _tagsOf(outbounds, 'blackhole').firstOrNull;
    routing['rules'] = [
      for (final rule in routing['rules'] as List)
        ?_withoutDirectInternet(rule, direct, blackhole),
    ];
    _forwardDnsThroughRules(outbounds, direct);
    return config;
  }

  static Set<String> _tagsOf(List<dynamic> outbounds, String protocol) => {
    for (final outbound in outbounds)
      if (outbound
          case {'protocol': final Object? value, 'tag': final String tag}
          when value == protocol)
        tag,
  };

  /// Returns the rule to keep in its place, or null when it should go.
  static Object? _withoutDirectInternet(
    Object? rule,
    Set<String> direct,
    String? blackhole,
  ) {
    if (rule is! Map<String, dynamic> ||
        !direct.contains(rule['outboundTag'])) {
      return rule;
    }
    final local = _strings(rule['ip']).where(_isLocal).toList();
    if (local.isNotEmpty) return {...rule, 'ip': local};
    if (blackhole == null) return null;
    // Panels keep torrents off their servers, and going direct would show the
    // user's real address while the app says it is hidden.
    if (_strings(rule['protocol']).contains('bittorrent')) {
      return {
        ...rule,
        'protocol': const ['bittorrent'],
        'outboundTag': blackhole,
      };
    }
    return _strings(rule['domain']).any(_isTorrentBootstrapHost)
        ? {...rule, 'outboundTag': blackhole}
        : null;
  }

  /// The core's own lookups lost their direct rule above. Queries it forwards
  /// dial through their outbound instead, and a loopback hands them to the rules
  /// because a dialer proxy cannot name a balancer.
  static void _forwardDnsThroughRules(
    List<dynamic> outbounds,
    Set<String> direct,
  ) {
    var forwarded = false;
    for (final outbound in outbounds.whereType<Map>()) {
      if (outbound['protocol'] != 'dns') continue;
      final stream =
          (outbound['streamSettings'] ??= <String, dynamic>{}) as Map;
      final sockopt = (stream['sockopt'] ??= <String, dynamic>{}) as Map;
      final proxy = sockopt['dialerProxy'];
      if (proxy != null && !direct.contains(proxy)) continue;
      sockopt['dialerProxy'] = _dnsForwardTag;
      forwarded = true;
    }
    if (forwarded) {
      outbounds.add({
        'tag': _dnsForwardTag,
        'protocol': 'loopback',
        'settings': {'inboundTag': _dnsForwardTag},
      });
    }
  }

  /// Domain entries may carry a matcher prefix such as `domain:` or `full:`.
  static bool _isTorrentBootstrapHost(String domain) =>
      _torrentBootstrapHosts.contains(domain.split(':').last);

  static bool _isLocal(String destination) {
    if (destination == 'geoip:private') return true;
    final range = _Cidr.parse(destination);
    return range != null && _localRanges.any((local) => local.contains(range));
  }

  /// Core accepts a single string wherever it accepts a list of them.
  static List<String> _strings(Object? value) => switch (value) {
    final String single => [single],
    final List<dynamic> list => list.whereType<String>().toList(),
    _ => const [],
  };
}

/// An address range; a plain address is a range of one.
final class _Cidr {
  const _Cidr(this.bytes, this.prefix);

  final List<int> bytes;
  final int prefix;

  static _Cidr? parse(String value) {
    final parts = value.split('/');
    final address = InternetAddress.tryParse(parts.first);
    if (address == null || parts.length > 2) return null;
    final bytes = address.rawAddress;
    final prefix = parts.length == 2
        ? int.tryParse(parts.last)
        : bytes.length * 8;
    if (prefix == null || prefix < 0 || prefix > bytes.length * 8) return null;
    return _Cidr(bytes, prefix);
  }

  bool contains(_Cidr other) {
    if (bytes.length != other.bytes.length || other.prefix < prefix) {
      return false;
    }
    for (var bit = 0; bit < prefix; bit++) {
      final mask = 0x80 >> (bit % 8);
      final index = bit ~/ 8;
      if (bytes[index] & mask != other.bytes[index] & mask) return false;
    }
    return true;
  }
}
