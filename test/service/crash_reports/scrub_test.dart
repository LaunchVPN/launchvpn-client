import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/crash_reports/scrub.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('an event leaves without the subscription link, addresses, email, '
      'HWID and DNS queries', () {
    final event = SentryEvent(
      serverName: 'Pixel of Ivan',
      message: SentryMessage(
        'update https://sub.launch.tel/aB3x?token=k9 for ivan@mail.ru failed',
      ),
      exceptions: [
        SentryException(
          type: 'SocketException',
          value:
              "Failed host lookup: 'de-1.example.net' "
              '(203.0.113.7:443, [2001:db8:85a3::8a2e:370:7334])',
        ),
      ],
      breadcrumbs: [
        Breadcrumb(
          message: 'device 3f2504e0-4f89-41d3-9a0c-0305e82c3301 registered',
          data: {
            'outbound': [
              'vless://3f2504e0-4f89-41d3-9a0c-0305e82c3301@nl.example.org:443',
            ],
            'dns': {'query': 'cdn.media.example.com', 'idn': 'vpn.сервер.рф'},
          },
        ),
      ],
      tags: {'server': '198.51.100.20'},
      contexts: Contexts()
        ..['flutter_error_details'] = {
          'information': ['Text "nl-2.example.org" overflowed'],
        },
      user: SentryUser(
        id: 'installation',
        email: 'ivan@mail.ru',
        ipAddress: '203.0.113.7',
      ),
    );

    final sent = jsonEncode(scrubEvent(event).toJson());

    for (final personal in [
      'Pixel of Ivan',
      'sub.launch.tel',
      'aB3x',
      'ivan@mail.ru',
      'de-1.example.net',
      '203.0.113.7',
      '2001:db8',
      '3f2504e0',
      'nl.example.org',
      'cdn.media.example.com',
      'сервер.рф',
      'nl-2.example.org',
      '198.51.100.20',
    ]) {
      expect(sent, isNot(contains(personal)), reason: personal);
    }
    expect(sent, contains('SocketException'));
    expect(sent, contains('Failed host lookup'));
  });

  test('keeps file names and times that look like addresses', () {
    expect(
      scrubText('lib/brand/app.dart failed at 12:30:45, see app.db'),
      'lib/brand/app.dart failed at 12:30:45, see app.db',
    );
  });
}
