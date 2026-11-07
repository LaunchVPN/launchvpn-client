import 'package:flutter/foundation.dart';
import 'package:onexray/service/connect/tunnel_probe.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// How the App handled a server that stopped answering, for Sentry.
@immutable
class ServerSilence {
  const ServerSilence({
    required this.location,
    required this.ran,
    required this.network,
    required this.failedChecks,
    required this.switched,
    required this.recovered,
  });

  /// The location's name as the App shows it.
  final String? location;

  /// How long the VPN had been running when its server went silent.
  final Duration ran;
  final NetworkKind network;
  final int failedChecks;

  /// The App restarted the session to switch servers.
  final bool switched;

  /// A check got through again, so the person kept the connection.
  final bool recovered;
}

/// The Sentry event for a server that stopped answering: where, on which
/// network and whether switching servers kept the person connected. Events
/// group by the outcome and the location, so a location whose servers keep
/// dying stands out. No server address leaves the device.
SentryEvent serverSilenceEvent(ServerSilence silence) {
  final outcome = silence.recovered ? 'recovered' : 'lost';
  final location = silence.location ?? 'unknown';
  return SentryEvent(
    level: silence.recovered ? SentryLevel.info : SentryLevel.warning,
    message: SentryMessage(
      silence.recovered
          ? 'Switching servers restored the connection'
          : 'The server stopped answering and the VPN went off',
    ),
    fingerprint: ['server-silence', outcome, location],
    tags: {
      'connection.outcome': outcome,
      'connection.location': location,
      'connection.network': silence.network.name,
    },
    contexts: Contexts()
      ..['connection_check'] = {
        'ran_seconds': silence.ran.inSeconds,
        'failed_checks': silence.failedChecks,
        'switched': silence.switched,
      },
  );
}
