import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';

/// The modes the App offers. «Приложения» is Smart routing behind OneXray's
/// allowed-apps tunnel, so only the chosen apps reach the VPN. It is Android
/// only, since iOS gives a VPN app no per-app choice.
enum ConnectionPreset {
  smart,
  allVpn,
  apps;

  /// In the order Home and «Режим» list them.
  static List<ConnectionPreset> offeredOn(ConnectionPlatform platform) =>
      platform == ConnectionPlatform.android ? values : const [smart, allVpn];

  /// Null for a stored mode the App does not offer, such as a custom route.
  static ConnectionPreset? of(
    ConnectionConfiguration configuration, {
    required ConnectionPlatform platform,
  }) => switch (configuration.connection.trafficMode) {
    TrafficMode.custom => null,
    _
        when platform == ConnectionPlatform.android &&
            configuration._android['appScope'] == _onlyChosen =>
      apps,
    TrafficMode.smart => smart,
    TrafficMode.allVpn => allVpn,
  };

  /// The chosen apps stay stored when another mode is picked.
  ConnectionConfiguration applyTo(ConnectionConfiguration configuration) =>
      configuration._with(
        trafficMode: this == allVpn ? TrafficMode.allVpn : TrafficMode.smart,
        android: {'appScope': this == apps ? _onlyChosen : 'all'},
      );

  static const _onlyChosen = 'included';
}

/// The apps «Приложения» sends through the VPN, as Android package names.
extension VpnApps on ConnectionConfiguration {
  List<String> get vpnApps =>
      (_android['includedAppPackageNames'] as List).cast<String>();

  ConnectionConfiguration withVpnApps(Iterable<String> packages) =>
      _with(android: {'includedAppPackageNames': packages.toList()});

  Map<String, dynamic> get _android =>
      policy.toJson()['android'] as Map<String, dynamic>;

  ConnectionConfiguration _with({
    TrafficMode? trafficMode,
    required Map<String, dynamic> android,
  }) {
    final next = policy.toJson();
    next['android'] = {..._android, ...android};
    return ConnectionConfiguration(
      connection: trafficMode == null
          ? connection
          : ConnectionSettings.fromJson({
              ...connection.toJson(),
              'trafficMode': trafficMode.name,
            }),
      policy: PlatformPolicy.fromJson(next),
    );
  }
}
