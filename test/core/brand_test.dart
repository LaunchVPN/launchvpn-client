import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/brand.dart';

const _upstreamId = 'net.yuandev.onexray';
const _upstreamTeam = '2CKAULFA9J';

String _read(String path) => File(path).readAsStringSync();

Iterable<File> _textFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (file) => const {
        '.kt',
        '.kts',
        '.xml',
        '.swift',
        '.plist',
        '.entitlements',
        '.pbxproj',
        '.strings',
      }.any(file.path.endsWith),
    );

void main() {
  group('Android matches the brand config', () {
    test('Gradle uses the Android ID', () {
      final gradle = _read('android/app/build.gradle.kts');

      expect(gradle, contains('namespace = "${Brand.androidId}"'));
      expect(gradle, contains('applicationId = "${Brand.androidId}"'));
      expect(
        _read('android/fastlane/Appfile'),
        contains('package_name("${Brand.androidId}")'),
      );
    });

    test('the manifest uses the name, deep link and automation actions', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');

      expect(manifest, contains('android:label="${Brand.name}"'));
      expect(manifest, contains('android:scheme="${Brand.scheme}"'));
      expect(
        manifest,
        contains('android:host="${Brand.subscriptionLinkHost}"'),
      );
      expect(manifest, contains('"${Brand.androidId}.action.START_VPN"'));
      expect(manifest, contains('"${Brand.androidId}.action.STOP_VPN"'));
    });

    test('Kotlin handles the automation actions of the manifest', () {
      final directory = Brand.androidId.replaceAll('.', '/');
      final receiver = _read(
        'android/app/src/main/kotlin/$directory/automation/VpnAutomationReceiver.kt',
      );

      expect(receiver, contains('"${Brand.androidId}.action.START_VPN"'));
      expect(receiver, contains('"${Brand.androidId}.action.STOP_VPN"'));
    });

    test('Kotlin sources live in the package of the Android ID', () {
      final directory = Brand.androidId.replaceAll('.', '/');

      expect(
        File('android/app/src/main/kotlin/$directory/MainActivity.kt')
            .existsSync(),
        isTrue,
      );
    });

    test('no upstream ID is left in Android sources', () {
      for (final file in _textFiles('android/app/src')) {
        expect(
          file.readAsStringSync(),
          isNot(contains(_upstreamId)),
          reason: file.path,
        );
      }
    });

    test('system-visible strings use the brand name', () {
      for (final file
          in Directory('android/app/src/main/res')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('strings.xml'))) {
        final text = file.readAsStringSync();
        expect(text, isNot(contains('OneXray')), reason: file.path);
        expect(text, contains(Brand.name), reason: file.path);
      }
    });
  });

  group('iOS matches the brand config', () {
    const appGroup = 'group.${Brand.iosId}';
    const cloudContainer = 'iCloud.${Brand.iosId}';

    test('every target builds under the iOS ID and the brand name', () {
      final project = _read('ios/Runner.xcodeproj/project.pbxproj');

      for (final suffix in const ['', '.tun', '.widget']) {
        expect(
          project,
          contains('PRODUCT_BUNDLE_IDENTIFIER = ${Brand.iosId}$suffix;'),
        );
      }
      expect(project, contains('CFBundleDisplayName = ${Brand.name};'));
      expect(project, isNot(contains(_upstreamTeam)));
    });

    test('Info.plist declares the name, deep link and iCloud container', () {
      final plist = _read('ios/Runner/Info.plist');

      expect(plist, contains('<string>${Brand.name}</string>'));
      expect(plist, contains('<string>${Brand.scheme}</string>'));
      expect(plist, contains('<key>$cloudContainer</key>'));
    });

    test('entitlements share one app group and iCloud container', () {
      for (final path in const [
        'ios/Runner/Runner.entitlements',
        'ios/tunnel/tunnel.entitlements',
        'ios/widget/widgetExtension.entitlements',
      ]) {
        expect(_read(path), contains('<string>$appGroup</string>'));
      }
      expect(
        _read('ios/Runner/Runner.entitlements'),
        contains('<string>$cloudContainer</string>'),
      );
    });

    test('Swift reaches the tunnel and app group of the iOS ID', () {
      final constants = _read('swift/All/Constants.swift');

      expect(constants, contains('groupAppGroupId = "$appGroup"'));
      expect(constants, contains('tunId = "${Brand.iosId}.tun"'));
      final widgetState = _read('swift/iOS/AppleWidgetState.swift');
      expect(widgetState, contains('appGroup = "$appGroup"'));
      expect(widgetState, contains('kind = "${Brand.iosId}.connection"'));
    });

    test('the widget opens the app through the brand scheme', () {
      expect(
        _read('ios/widget/widget.swift'),
        contains('"${Brand.scheme}://widget/connect"'),
      );
    });

    test('fastlane signs the iOS ID', () {
      expect(
        _read('ios/fastlane/Appfile'),
        contains("app_identifier '${Brand.iosId}'"),
      );
      expect(_read('ios/fastlane/Fastfile'), contains("'${Brand.iosId}.tun'"));
    });

    test('the launch screen has the background of the app', () {
      final match = RegExp(
        r'<color key="backgroundColor" red="([\d.]+)" green="([\d.]+)" blue="([\d.]+)"',
      ).firstMatch(_read('ios/Runner/Base.lproj/LaunchScreen.storyboard'))!;

      expect(
        Color.from(
          alpha: 1,
          red: double.parse(match[1]!),
          green: double.parse(match[2]!),
          blue: double.parse(match[3]!),
        ).toARGB32(),
        BrandColors.bg.toARGB32(),
      );
    });

    test('no upstream identity is left in iOS sources', () {
      for (final file in _textFiles('ios')) {
        final text = file.readAsStringSync();
        expect(text, isNot(contains(_upstreamId)), reason: file.path);
        expect(text, isNot(contains('OneXray')), reason: file.path);
      }
      for (final file in _textFiles('swift/iOS')) {
        expect(
          file.readAsStringSync(),
          isNot(contains(_upstreamId)),
          reason: file.path,
        );
      }
    });
  });

  test('translations name the app by its brand name', () {
    for (final file in Directory('lib/l10n').listSync().whereType<File>().where(
      (file) => file.path.endsWith('.arb'),
    )) {
      final messages = (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, Object?>();
      for (final MapEntry(:key, :value) in messages.entries) {
        if (key.startsWith('@')) continue;
        expect(value, isNot(contains('OneXray')), reason: '${file.path}: $key');
      }
    }
  });
}
