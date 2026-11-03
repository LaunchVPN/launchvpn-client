/// Where the installed build comes from, fixed at build time.
///
/// CI passes `--dart-define=LAUNCHVPN_DISTRIBUTION=apk` to the APK it publishes.
/// Every other build, iOS and local runs included, counts as a store build,
/// which leaves updates to the store.
enum AppDistribution {
  /// Installed from an APK, so the App itself looks for a newer release.
  apk,
  store;

  static const current =
      String.fromEnvironment('LAUNCHVPN_DISTRIBUTION') == 'apk' ? apk : store;
}
