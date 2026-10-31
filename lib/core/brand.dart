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

  /// Host of the deep link that adds a subscription.
  static const subscriptionLinkHost = 'sub';

  /// Host of upstream's share links, read by upstream's paste and QR import.
  /// Android does not register it, and iOS rejects it after opening the app.
  static const appLinkHost = 'app';

  /// Deep links add subscriptions from this domain and its subdomains only.
  static const subscriptionDomain = 'launch.tel';

  /// Leading User-Agent product. Panels pick the Xray JSON template by it.
  static const subscriptionClient = 'v2rayN';

  static const githubRepository = 'LaunchVPN/launchvpn-client';
}
