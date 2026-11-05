import 'package:onexray/service/connect/policy_section.dart';
import 'package:onexray/service/connect/runtime.dart';

/// «Не отключать VPN»: on iOS the tunnel gets OneXray's always-on rule, so the
/// system connects it on any network, after a restart too. Android has its own
/// always-on VPN setting, so the App offers this on iOS only.
extension KeepVpnOn on ConnectionConfiguration {
  bool get keepVpnOn => policySection(_apple)[_alwaysOn] == true;

  ConnectionConfiguration withKeepVpnOn(bool value) =>
      withPolicySection(_apple, {_alwaysOn: value});

  static const _apple = 'apple';
  static const _alwaysOn = 'alwaysOn';
}
