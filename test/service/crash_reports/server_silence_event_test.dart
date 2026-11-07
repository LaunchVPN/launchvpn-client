import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/crash_reports/server_silence_event.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

ServerSilence _silence({required bool recovered}) => ServerSilence(
  location: 'Германия',
  ran: const Duration(hours: 2, minutes: 14),
  network: NetworkKind.wifi,
  failedChecks: recovered ? 2 : 4,
  switched: true,
  recovered: recovered,
);

void main() {
  test('a switch that kept the connection is a quieter event', () {
    final event = serverSilenceEvent(_silence(recovered: true));

    expect(event.level, SentryLevel.info);
    expect(
      event.message?.formatted,
      'Switching servers restored the connection',
    );
    expect(event.fingerprint, ['server-silence', 'recovered', 'Германия']);
    expect(event.tags, {
      'connection.outcome': 'recovered',
      'connection.location': 'Германия',
      'connection.network': 'wifi',
    });
    expect(event.contexts['connection_check'], {
      'ran_seconds': 8040,
      'failed_checks': 2,
      'switched': true,
    });
  });

  test('a person left without a connection is a warning', () {
    final event = serverSilenceEvent(_silence(recovered: false));

    expect(event.level, SentryLevel.warning);
    expect(event.fingerprint, ['server-silence', 'lost', 'Германия']);
    expect(event.contexts['connection_check']['failed_checks'], 4);
  });
}
