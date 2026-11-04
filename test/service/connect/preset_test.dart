import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/preset.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';

const _android = ConnectionPlatform.android;

void main() {
  final stored = ConnectionConfiguration();

  test('Apps is offered on Android only', () {
    expect(ConnectionPreset.offeredOn(_android), [
      ConnectionPreset.smart,
      ConnectionPreset.allVpn,
      ConnectionPreset.apps,
    ]);
    expect(ConnectionPreset.offeredOn(ConnectionPlatform.ios), [
      ConnectionPreset.smart,
      ConnectionPreset.allVpn,
    ]);
  });

  test('Apps sends only the chosen apps through the tunnel', () {
    final next = ConnectionPreset.apps.applyTo(
      stored.withVpnApps([
        'org.telegram.messenger',
        'com.google.android.youtube',
      ]),
    );

    final tun = next.policy.toTun(_android);
    expect(tun.perAppVPNMode, 'allow');
    expect(tun.allowAppList, [
      'org.telegram.messenger',
      'com.google.android.youtube',
    ]);
    expect(
      ConnectionPreset.of(next, platform: _android),
      ConnectionPreset.apps,
    );
  });

  test('Apps routes like Smart', () {
    final next = ConnectionPreset.apps.applyTo(
      ConnectionPreset.allVpn.applyTo(stored.withVpnApps(['a.b'])),
    );

    expect(next.connection.trafficMode, TrafficMode.smart);
  });

  test(
    'leaving Apps sends every app through the tunnel and keeps the list',
    () {
      final apps = ConnectionPreset.apps.applyTo(stored.withVpnApps(['a.b']));

      for (final preset in [ConnectionPreset.smart, ConnectionPreset.allVpn]) {
        final next = preset.applyTo(apps);
        expect(next.policy.toTun(_android).allowAppList, isEmpty);
        expect(next.vpnApps, ['a.b']);
        expect(ConnectionPreset.of(next, platform: _android), preset);
      }
    },
  );

  test('another platform reads an Android list as Smart', () {
    final apps = ConnectionPreset.apps.applyTo(stored.withVpnApps(['a.b']));

    expect(
      ConnectionPreset.of(apps, platform: ConnectionPlatform.ios),
      ConnectionPreset.smart,
    );
  });

  test('a custom route is no preset, whatever the app scope', () {
    final custom = ConnectionConfiguration(
      connection: ConnectionSettings(trafficMode: TrafficMode.custom),
    );

    expect(ConnectionPreset.of(custom, platform: _android), isNull);
    expect(
      ConnectionPreset.of(
        ConnectionConfiguration(
          connection: custom.connection,
          policy: ConnectionPreset.apps
              .applyTo(stored.withVpnApps(['a.b']))
              .policy,
        ),
        platform: _android,
      ),
      isNull,
    );
  });
}
