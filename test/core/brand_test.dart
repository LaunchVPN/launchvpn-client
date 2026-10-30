import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/brand.dart';

const _upstreamId = 'net.yuandev.onexray';

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
      expect(manifest, contains('android:host="${Brand.appLinkHost}"'));
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
}
