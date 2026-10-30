/// The LaunchVPN identity: names, platform IDs, deep links and client strings.
///
/// Native projects cannot import Dart, so they repeat these values literally.
/// `test/core/brand_test.dart` fails until every native copy matches this file.
abstract final class Brand {
  static const name = 'LaunchVPN';

  static const androidId = 'com.launchvpn.app';

  /// Temporary ID for the personal Apple account. It becomes `com.launchvpn.app`
  /// once the Apple organization exists.
  static const iosId = 'com.launchvpn.dev';

  static const scheme = 'launchvpn';
  static const appLinkHost = 'app';

  /// Leading User-Agent product. Panels pick the Xray JSON template by it.
  static const subscriptionClient = 'v2rayN';

  static const githubRepository = 'LaunchVPN/launchvpn-client';
}
