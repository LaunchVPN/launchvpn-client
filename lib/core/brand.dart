/// The LaunchVPN identity: names, platform IDs, deep links and client strings.
///
/// Native projects cannot import Dart, so they repeat these values literally.
/// `test/core/brand_test.dart` fails until every native copy matches this file.
abstract final class Brand {
  static const name = 'LaunchVPN';

  /// The name as the logo draws it.
  static const wordmark = 'launchvpn';

  static const androidId = 'com.launchvpn.app';

  /// Temporary ID for the personal Apple account. It becomes `com.launchvpn.app`
  /// once the Apple organization exists.
  static const iosId = 'com.launchvpn.dev';

  static const scheme = 'launchvpn';

  /// Host of the deep link that adds a subscription.
  static const subscriptionLinkHost = 'sub';

  /// Host of the deep link the browser returns to after Telegram's sign-in.
  static const authLinkHost = 'auth';

  /// Host of upstream's share links, read by upstream's paste and QR import.
  /// Android does not register it, and iOS rejects it after opening the app.
  static const appLinkHost = 'app';

  /// Deep links add subscriptions from this domain and its subdomains only.
  static const subscriptionDomain = 'launch.tel';

  /// Where an APK build sends the person to renew. Store builds offer no
  /// payment.
  static const renewalUrl = 'https://app.$subscriptionDomain';

  /// Support in Telegram, for a subscription whose panel names none.
  static const supportUrl = 'https://t.me/launchbotsupport';

  /// The account API. Local runs point it at another backend with
  /// `--dart-define=LAUNCHVPN_API_URL=http://10.0.2.2:8080`.
  static const apiUrl = String.fromEnvironment(
    'LAUNCHVPN_API_URL',
    defaultValue: 'https://app.$subscriptionDomain',
  );

  /// Leading User-Agent product. Panels pick the Xray JSON template by it.
  static const subscriptionClient = 'v2rayN';

  static const githubRepository = 'LaunchVPN/launchvpn-client';

  /// Crash reports. A DSN only lets one send events, so it is not a secret.
  static const sentryDsn =
      'https://b8a45d71119187498301161db2d2ad72@o4512378829602816.ingest.de.sentry.io/4512378850443344';
}
