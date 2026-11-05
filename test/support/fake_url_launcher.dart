import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records the links the screen opens instead of leaving the test.
final class FakeUrlLauncher extends UrlLauncherPlatform {
  final opened = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

/// Puts a [FakeUrlLauncher] in place of the platform's for this test.
FakeUrlLauncher useFakeUrlLauncher() {
  final launcher = FakeUrlLauncher();
  final previous = UrlLauncherPlatform.instance;
  UrlLauncherPlatform.instance = launcher;
  addTearDown(() => UrlLauncherPlatform.instance = previous);
  return launcher;
}
