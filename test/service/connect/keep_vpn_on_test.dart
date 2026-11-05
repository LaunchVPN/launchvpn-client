import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/keep_vpn_on.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';

const _ios = ConnectionPlatform.ios;

void main() {
  final stored = ConnectionConfiguration();

  test('is off by default and gives the tunnel no rules', () {
    final tun = stored.policy.toTun(_ios);

    expect(stored.keepVpnOn, isFalse);
    expect(tun.onDemandEnabled, isFalse);
    expect(tun.onDemandRules, isEmpty);
  });

  test('on, the tunnel connects on any network', () {
    final next = stored.withKeepVpnOn(true);
    final tun = next.policy.toTun(_ios);

    expect(next.keepVpnOn, isTrue);
    expect(tun.onDemandEnabled, isTrue);
    expect(tun.onDemandRules?.map((rule) => rule.toJson()), [
      {'mode': 'connect', 'interfaceType': 'any'},
    ]);
  });

  test('off again, the tunnel has no rules', () {
    final tun = stored
        .withKeepVpnOn(true)
        .withKeepVpnOn(false)
        .policy
        .toTun(_ios);

    expect(tun.onDemandEnabled, isFalse);
    expect(tun.onDemandRules, isEmpty);
  });
}
