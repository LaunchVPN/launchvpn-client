import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/connect/connection_permissions.dart';
import 'package:onexray/service/connect/coordinator.dart';

void main() {
  late List<String> steps;
  late _RecordingCoordinator coordinator;

  setUp(() {
    steps = [];
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    coordinator = _RecordingCoordinator(db, steps);
    addTearDown(coordinator.dispose);
  });

  ConnectionPermissions permissions({
    PlatformPermissionState vpnAnswer = PlatformPermissionState.granted,
  }) => ConnectionPermissions(
    coordinator,
    requestVpn: () async {
      steps.add('vpn');
      return PlatformPermissionResult(
        kind: PlatformPermissionKind.androidVpn,
        state: vpnAnswer,
      );
    },
    requestNotifications: () async => steps.add('notifications'),
  );

  void needVpnPermission() {
    coordinator.state.value = ConnectionView(
      issue: 'permissionRequired',
      permission: PlatformPermissionResult(
        kind: PlatformPermissionKind.androidVpn,
        state: PlatformPermissionState.notDetermined,
      ),
    );
  }

  test(
    'the first connection asks for VPN, then notifications, then connects',
    () async {
      needVpnPermission();

      await permissions().connect();

      expect(steps, ['vpn', 'notifications', 'connect']);
    },
  );

  test(
    'a refused VPN prompt is not followed by a notification prompt',
    () async {
      needVpnPermission();

      await permissions(vpnAnswer: PlatformPermissionState.denied).connect();

      expect(steps, ['vpn', 'connect']);
    },
  );

  test('a failed notification prompt still connects', () async {
    needVpnPermission();

    await ConnectionPermissions(
      coordinator,
      requestVpn: () async => PlatformPermissionResult(
        kind: PlatformPermissionKind.androidVpn,
        state: PlatformPermissionState.granted,
      ),
      requestNotifications: () async => throw StateError('in progress'),
    ).connect();

    expect(steps, ['connect']);
  });

  test('with permission granted, a connection asks nothing', () async {
    await permissions().connect();

    expect(steps, ['connect']);
  });
}

final class _RecordingCoordinator extends ConnectionCoordinator {
  _RecordingCoordinator(AppDatabase database, this.steps)
    : super(database: database, disposeStatus: () {});

  final List<String> steps;

  @override
  Future<void> connect() async => steps.add('connect');
}
