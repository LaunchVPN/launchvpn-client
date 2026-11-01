import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/servers/subscription/panel_info.dart';

void main() {
  SubscriptionPanelInfo parse(Map<String, List<String>> headers) =>
      SubscriptionPanelInfo.fromHeaders(Headers.fromMap(headers));

  test('reads the headers a Remnawave panel sends', () {
    final info = parse({
      'Profile-Title': ['base64:TGF1bmNoVlBOIHwg0J/QvtC00LTQtdGA0LbQutCw'],
      'Profile-Update-Interval': ['12'],
      'Support-Url': ['https://t.me/support'],
    });

    expect(info.title, 'LaunchVPN | Поддержка');
    expect(info.updateIntervalHours, 12);
    expect(info.supportUrl, 'https://t.me/support');
  });

  test('accepts a plain title', () {
    expect(
      parse({
        'profile-title': ['  LaunchVPN  '],
      }).title,
      'LaunchVPN',
    );
  });

  test('reads an announcement with its line breaks', () {
    expect(
      parse({
        'announce': ['base64:0KDQsNCx0L7RgtGLCtCyIDAyOjAw'],
      }).announce,
      'Работы\nв 02:00',
    );
    expect(
      parse({
        'announce': ['  Plain text  '],
      }).announce,
      'Plain text',
    );
  });

  test('no headers leave every value unknown', () {
    final info = parse({});

    expect(info.title, isNull);
    expect(info.announce, isNull);
    expect(info.updateIntervalHours, isNull);
    expect(info.supportUrl, isNull);
  });

  for (final value in ['0', '-1', '1.5', 'soon', '', '99999999999999999999']) {
    test('interval "$value" is unknown', () {
      expect(
        parse({
          'profile-update-interval': [value],
        }).updateIntervalHours,
        isNull,
      );
    });
  }

  for (final value in ['base64:not base64!', 'base64:/w==', 'base64:', '   ']) {
    test('title "$value" is unknown', () {
      expect(
        parse({
          'profile-title': [value],
        }).title,
        isNull,
      );
    });
  }

  test('an announcement that does not decode is unknown', () {
    expect(
      parse({
        'announce': ['base64:not base64!'],
      }).announce,
      isNull,
    );
  });

  for (final value in [
    'http://t.me/support',
    'tg://resolve?domain=support',
    'https://',
    't.me/support',
  ]) {
    test('support link "$value" is unknown', () {
      expect(
        parse({
          'support-url': [value],
        }).supportUrl,
        isNull,
      );
    });
  }

  test('a repeated header is ambiguous, others still count', () {
    final info = parse({
      'profile-update-interval': ['12', '24'],
      'support-url': ['https://t.me/support'],
    });

    expect(info.updateIntervalHours, isNull);
    expect(info.supportUrl, 'https://t.me/support');
  });
}
