import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/shared/notification/service.dart';

/// Connects on the user's command, asking first for the permissions the
/// connection needs. LaunchVPN asks here rather than at launch, so the first
/// tap on Home or the Android Tile is what brings up the system prompts.
final class ConnectionPermissions {
  ConnectionPermissions(
    this._coordinator, {
    Future<PlatformPermissionResult> Function()? requestVpn,
    Future<void> Function()? requestNotifications,
  }) : _requestVpn = requestVpn ?? AppHostApi().requestPlatformPermission,
       _requestNotifications =
           requestNotifications ?? NotificationService().requestPermission;

  final ConnectionCoordinator _coordinator;
  final Future<PlatformPermissionResult> Function() _requestVpn;
  final Future<void> Function() _requestNotifications;

  /// Notifications are asked only right after the VPN consent, so a refusal
  /// does not come back with every connection.
  Future<void> connect() async {
    final view = _coordinator.state.value;
    if (view.issue == 'permissionRequired' && view.permission != null) {
      final vpn = await _requestVpn();
      if (vpn.state == PlatformPermissionState.granted) {
        await _askForNotifications();
      }
    }
    await _coordinator.connect();
  }

  Future<void> _askForNotifications() async {
    try {
      await _requestNotifications();
    } catch (error, stackTrace) {
      // The VPN runs without notifications; only its status line is hidden.
      ygLogger('request notifications failed: $error\n$stackTrace');
    }
  }
}
