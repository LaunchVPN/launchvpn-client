import 'dart:async';

import 'package:collection/collection.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/resolver.dart';
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
  ///
  /// A start measures up to five random servers, so it stays quick. With
  /// [everyServer], as after the session's server went silent, it measures
  /// the whole group, batch after batch, so a single live server is found;
  /// a group where none answers then fails as silent instead of starting.
  Future<ResolvedProfile> pick(
    ResolvedProfile profile, {
    Future<void>? cancelled,
    bool everyServer = false,
  }) async {
    final config = profile.config;
    final servers = _candidates(config);
    if (servers.length < (everyServer ? 1 : 2)) return profile;
    final batches = everyServer
        ? servers.slices(PingBatchRunner.maxBatchSize).toList()
        : [servers.shuffled().take(PingBatchRunner.maxBatchSize).toList()];
    final answer = await Future.any([
      _fastest(batches),
      if (cancelled != null) cancelled.then((_) => null),
    ]).timeout(_budget * batches.length, onTimeout: () => null);
    if (answer == null) return profile;
    final winner = answer.winner;
    if (winner == null) {
      if (everyServer) {
        throw ConnectionResolutionException(
          ConnectionResolutionFailure.insufficientHealthyServers,
          requiredCount: 1,
          availableCount: 0,
        );
      }
      return profile;
    }
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
        when _matchesAllTraffic(rule)) {
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

  bool _matchesAllTraffic(Map<String, dynamic> rule) {
    if (!_catchAllRuleKeys.containsAll(rule.keys)) return false;
    final network = rule['network'];
    return network == null ||
        ('$network'.contains('tcp') && '$network'.contains('udp'));
  }

  /// The fastest server across [batches], or none when every one was
  /// measured and stayed silent. Null when the check itself failed, which
  /// must never fail the connection it serves.
  Future<({Map<String, dynamic>? winner})?> _fastest(
    List<List<Map<String, dynamic>>> batches,
  ) async {
    try {
      Map<String, dynamic>? winner;
      var best = 0;
      for (final servers in batches) {
        final results = await _measure([
          for (final server in servers) encodeSingleOutbound(server),
        ], timeoutSeconds: _timeoutSeconds);
        for (final (index, result) in results.indexed) {
          if (result.success && (winner == null || result.delay < best)) {
            winner = servers[index];
            best = result.delay;
          }
        }
      }
      return (winner: winner);
    } catch (error) {
      ygLogger('Check first server failed (${error.runtimeType})');
      return null;
    }
  }
}
