import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/runtime.dart';

/// Reads and patches one platform section of the stored tunnel policy, such
/// as `android` or `apple`. Keys the patch leaves out keep their values.
extension PolicySection on ConnectionConfiguration {
  Map<String, dynamic> policySection(String name) =>
      policy.toJson()[name] as Map<String, dynamic>;

  ConnectionConfiguration withPolicySection(
    String name,
    Map<String, dynamic> patch,
  ) {
    final next = policy.toJson();
    next[name] = {...next[name] as Map<String, dynamic>, ...patch};
    return ConnectionConfiguration(
      connection: connection,
      policy: PlatformPolicy.fromJson(next),
    );
  }
}
