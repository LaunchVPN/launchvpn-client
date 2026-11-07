import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// The Sentry event for a tunnel run iOS ended: why, after how long and how
/// close it came to the memory limit. Events group by the reason.
SentryEvent tunnelStopEvent(TunnelStop stop) {
  final reason = stop.reason;
  final ran = Duration(milliseconds: stop.endedAtMs - stop.startedAtMs);
  final memory = stop.memory;
  return SentryEvent(
    level: SentryLevel.warning,
    timestamp: DateTime.fromMillisecondsSinceEpoch(stop.endedAtMs, isUtc: true),
    message: SentryMessage(
      reason == null
          ? 'The VPN process ended without a stop: a crash or the memory limit'
          : 'iOS stopped the VPN: $reason',
    ),
    fingerprint: ['tunnel-stop', reason ?? 'no-stop'],
    tags: {'tunnel.stop_reason': reason ?? 'none'},
    contexts: Contexts()
      ..['tunnel'] = {
        'ran_seconds': ran.inSeconds,
        if (memory != null) ...{
          'footprint_mb': _megabytes(memory.footprint),
          'peak_mb': _megabytes(memory.peak),
          'limit_mb': _megabytes(memory.limit),
        },
      },
  );
}

int _megabytes(int bytes) => (bytes / 1048576).round();
