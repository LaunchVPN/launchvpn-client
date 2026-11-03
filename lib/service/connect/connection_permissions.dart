import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/shared/notification/service.dart';

/// Shows the App's own explanation before the system VPN prompt and answers
/// whether the person chose to go on.
typedef VpnPermissionExplanation = Future<bool> Function();

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

  /// Until the person once chooses to go on, [explain] comes before the system
  /// prompt, and declining it leaves the connection off. Notifications are
  /// asked only right after the VPN consent, so a refusal does not come back
  /// with every connection.
  Future<void> connect({required VpnPermissionExplanation explain}) async {
    final view = _coordinator.state.value;
    if (view.issue == 'permissionRequired' && view.permission != null) {
      if (!await _explained(explain)) return;
      final vpn = await _requestVpn();
      if (vpn.state == PlatformPermissionState.granted) {
        await _askForNotifications();
      }
    }
    await _coordinator.connect();
  }

  Future<bool> _explained(VpnPermissionExplanation explain) async {
    final preferences = PreferencesKey();
    if (await preferences.readVpnPermissionExplained()) return true;
    if (!await explain()) return false;
    await preferences.saveVpnPermissionExplained();
    return true;
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
