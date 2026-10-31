import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';

Uri _link(String url) => Uri(
  scheme: 'launchvpn',
  host: 'sub',
  path: '/add',
  queryParameters: {'url': url},
);

void main() {
  group('accepts', () {
    for (final url in [
      'https://launch.tel/sub/token',
      'https://sub.launch.tel/token',
      'https://SUB.LAUNCH.TEL/token',
    ]) {
      test(url, () {
        expect(SubscriptionDeepLink.parse(_link(url))?.url, isNotNull);
      });
    }

    test('a percent-encoded subscription URL with its own query', () {
      final link = SubscriptionDeepLink.parse(
        Uri.parse(
          'launchvpn://sub/add?url=https%3A%2F%2Fsub.launch.tel%2Ftoken%3Fa%3D1',
        ),
      );

      expect(link?.url, 'https://sub.launch.tel/token?a=1');
    });
  });

  group('rejects another provider', () {
    for (final url in [
      'https://provider.example/sub/token',
      'https://evillaunch.tel/token',
      'https://launch.tel.provider.example/token',
      'https://launch.tel@provider.example/token',
      'https://provider.example/launch.tel',
    ]) {
      test(url, () {
        expect(SubscriptionDeepLink.parse(_link(url)), isNull);
      });
    }
  });

  group('rejects a malformed subscription URL', () {
    for (final url in [
      'http://sub.launch.tel/token',
      'https://user:secret@sub.launch.tel/token',
      'not a url',
      '',
    ]) {
      test('"$url"', () {
        expect(SubscriptionDeepLink.parse(_link(url)), isNull);
      });
    }
  });

  group('rejects any other link shape', () {
    for (final link in [
      'launchvpn://app/sub/add?url=https://sub.launch.tel/token',
      'launchvpn://app/config/add?type=raw&data=e30',
      'launchvpn://sub/remove?url=https://sub.launch.tel/token',
      'launchvpn://sub/add',
      'launchvpn://sub/add?url=https://sub.launch.tel/a&url=https://sub.launch.tel/b',
      'launchvpn://sub/add?url=https://sub.launch.tel/token&panel=generic',
      'launchvpn://sub:1/add?url=https://sub.launch.tel/token',
      'launchvpn://user@sub/add?url=https://sub.launch.tel/token',
      'other://sub/add?url=https://sub.launch.tel/token',
    ]) {
      test(link, () {
        expect(SubscriptionDeepLink.parse(Uri.parse(link)), isNull);
      });
    }
  });
}
