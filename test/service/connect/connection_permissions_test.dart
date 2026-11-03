import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/connect/connection_permissions.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late List<String> steps;
  late _RecordingCoordinator coordinator;

  // PreferencesKey keeps the first platform it sees, so tests share one store.
  final store = _Store();
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = store);

  setUp(() async {
    steps = [];
    store.broken = false;
    await SharedPreferencesAsync().clear();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    coordinator = _RecordingCoordinator(db, steps);
    addTearDown(coordinator.dispose);
  });

  ConnectionPermissions permissions({
    PlatformPermissionState vpnAnswer = PlatformPermissionState.granted,
    Future<void> Function()? requestNotifications,
  }) => ConnectionPermissions(
    coordinator,
    requestVpn: () async {
      steps.add('vpn');
      return PlatformPermissionResult(
        kind: PlatformPermissionKind.androidVpn,
        state: vpnAnswer,
      );
    },
    requestNotifications:
        requestNotifications ?? () async => steps.add('notifications'),
  );

  Future<bool> Function() answer(bool goOn) => () async {
    steps.add('explain');
    return goOn;
  };

  void needVpnPermission() {
    coordinator.state.value = ConnectionView(
      issue: 'permissionRequired',
      permission: PlatformPermissionResult(
        kind: PlatformPermissionKind.androidVpn,
        state: PlatformPermissionState.notDetermined,
      ),
    );
  }

  test('the first connection explains, then asks for VPN and notifications, then connects', () async {
    needVpnPermission();

    await permissions().connect(explain: answer(true));

    expect(steps, ['explain', 'vpn', 'notifications', 'connect']);
  });

  test('"Not now" asks the system nothing and does not connect, so the screen comes back', () async {
    needVpnPermission();

    await permissions().connect(explain: answer(false));
    await permissions().connect(explain: answer(false));

    expect(steps, ['explain', 'explain']);
  });

  test(
    'after one "Continue" the system asks directly, even when VPN was refused',
    () async {
      needVpnPermission();

      await permissions(vpnAnswer: PlatformPermissionState.denied)
          .connect(explain: answer(true));
      await permissions(vpnAnswer: PlatformPermissionState.denied)
          .connect(explain: answer(true));

      expect(steps, ['explain', 'vpn', 'connect', 'vpn', 'connect']);
    },
  );

  test('a failed notification prompt still connects', () async {
    needVpnPermission();

    await permissions(
      requestNotifications: () async => throw StateError('in progress'),
    ).connect(explain: answer(true));

    expect(steps, ['explain', 'vpn', 'connect']);
  });

  test('broken storage still explains and connects', () async {
    needVpnPermission();
    store.broken = true;

    await permissions().connect(explain: answer(true));

    expect(steps, ['explain', 'vpn', 'notifications', 'connect']);
  });

  test('with permission granted, a connection asks nothing', () async {
    await permissions().connect(explain: answer(true));

    expect(steps, ['connect']);
  });
}

final class _Store extends InMemorySharedPreferencesAsync {
  _Store() : super.empty();

  bool broken = false;

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async {
    if (broken) throw StateError('unreadable');
    return super.getBool(key, options);
  }

  @override
  Future<bool> setBool(
    String key,
    bool value,
    SharedPreferencesOptions options,
  ) async {
    if (broken) throw StateError('unwritable');
    return super.setBool(key, value, options);
  }
}

final class _RecordingCoordinator extends ConnectionCoordinator {
  _RecordingCoordinator(AppDatabase database, this.steps)
    : super(database: database, disposeStatus: () {});

  final List<String> steps;

  @override
  Future<void> connect() async => steps.add('connect');
}
