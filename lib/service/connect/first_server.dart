import 'dart:async';

import 'package:collection/collection.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/shared/ping/batch.dart';

/// Measures single-outbound configs together, one result per config.
typedef MeasureServers = Future<List<PingBatchResult>> Function(
  List<String> outboundJsons, {
  required int timeoutSeconds,
});

/// Puts a server that answers first in a provider group, for one session.
///
/// A balancer that chooses by measurements has none when the core starts, so
/// the core sends traffic to the group's first outbound. The core's DNS flow
/// opens in that moment and stays there, and a dead first server then stalls
/// every lookup long after the measurements arrive.
class FirstServerPicker {
  FirstServerPicker({required this._measure});

  static const _timeoutSeconds = 2;

  /// A native batch waits its turn behind one already running.
  static const _budget = Duration(seconds: _timeoutSeconds + 1);
  static const _measuringStrategies = {'leastLoad', 'leastPing'};
  static const _catchAllRuleKeys = {
    'type',
    'network',
    'ruleTag',
    'balancerTag',
  };

  final MeasureServers _measure;

  /// Returns [profile] as it is when no server answers within the budget, or
  /// once [cancelled] completes.
  Future<ResolvedProfile> pick(
    ResolvedProfile profile, {
    Future<void>? cancelled,
  }) async {
    final config = profile.config;
    final servers = _candidates(config);
    if (servers.length < 2) return profile;
    final winner = await Future.any([
      _fastest(servers.shuffled().take(PingBatchRunner.maxBatchSize).toList()),
      if (cancelled != null) cancelled.then((_) => null),
    ]).timeout(_budget, onTimeout: () => null);
    if (winner == null) return profile;
    (config['outbounds'] as List)
      ..remove(winner)
      ..insert(0, winner);
    return profile.withConfig(config);
  }

  /// The servers the group's catch-all rule balances over. Traffic that a
  /// narrower last rule leaves unmatched really is meant for the first outbound.
  /// Malformed graphs have none and stay as they are for Core validation.
  List<Map<String, dynamic>> _candidates(Map<String, dynamic> config) {
    if (config
        case {
          'outbounds': final List<dynamic> outbounds,
          'routing': {
            'rules': [..., final Map<String, dynamic> rule],
            'balancers': final List<dynamic> balancers,
          },
        }
        when _catchAllRuleKeys.containsAll(rule.keys)) {
      final balancer = balancers
          .whereType<Map<String, dynamic>>()
          .firstWhereOrNull(
            (balancer) => balancer['tag'] == rule['balancerTag'],
          );
      if (balancer
          case {
            'selector': final List<dynamic> selector,
            'strategy': {'type': final String strategy},
          }
          when _measuringStrategies.contains(strategy)) {
        final prefixes = selector.whereType<String>();
        return [
          for (final outbound in outbounds.whereType<Map<String, dynamic>>())
            if (outbound['tag'] case final String outboundTag
                when prefixes.any(outboundTag.startsWith) &&
                    isStandaloneServer(outbound))
              outbound,
        ];
      }
    }
    return const [];
  }

  /// A failed check must never fail the connection it serves.
  Future<Map<String, dynamic>?> _fastest(
    List<Map<String, dynamic>> servers,
  ) async {
    try {
      final results = await _measure([
        for (final server in servers) encodeSingleOutbound(server),
      ], timeoutSeconds: _timeoutSeconds);
      final answered = results.indexed.where((item) => item.$2.success);
      if (answered.isEmpty) return null;
      return servers[minBy(answered, (item) => item.$2.delay)!.$1];
    } catch (error) {
      ygLogger('Check first server failed (${error.runtimeType})');
      return null;
    }
  }
}
