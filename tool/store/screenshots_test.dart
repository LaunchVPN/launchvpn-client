// Renders the store screenshots, icon and banner into fastlane's folders:
//
//   flutter test tool/store/screenshots_test.dart
//
// Every screen is the App's own, pumped on test data, so no subscription link,
// server address or personal data can reach a store. It lives outside `test/`
// because fonts render differently on each machine and CI must not compare it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/shader_backdrop.dart';

import 'scenes.dart';
import 'store.dart';

void main() {
  setUpAll(() async {
    await loadFonts();
    // The backdrop's shader loads once per run. Started inside a test's fake
    // clock, it would never finish for the tests after it.
    await const ShaderBackdrop(child: SizedBox()).loadProgram();
  });

  for (final language in StoreLanguage.values) {
    for (final device in StoreDevice.values) {
      for (final (index, shot) in Shot.values.indexed) {
        testWidgets('${device.name} ${language.name} ${shot.name}', (
          tester,
        ) async {
          final scene = await Scene.start(tester, shot, device, language);
          await render(
            tester,
            device.canvas,
            device.pixelRatio,
            StoreFrame(
              device: device,
              caption: shot.caption(language),
              screen: scene.app,
            ),
          );
          await scene.settle(tester);
          await save(tester, device.screenshot(language, index + 1, shot.name));
          await scene.close(tester);
        }, variant: TargetPlatformVariant.only(device.platform.target));
      }
    }
  }

  for (final language in StoreLanguage.values) {
    testWidgets('play icon ${language.name}', (tester) async {
      await render(tester, const Size.square(512), 1, const StoreIcon());
      await save(tester, StoreDevice.playImage(language, 'icon.png'));
    });

    testWidgets('play banner ${language.name}', (tester) async {
      await render(tester, const Size(1024, 500), 1, const StoreBanner());
      await tester.runAsync(() => Future<void>.delayed(Durations.short2));
      await tester.pump();
      await save(tester, StoreDevice.playImage(language, 'featureGraphic.png'));
    });
  }
}

/// The fonts `pubspec.yaml` bundles, instead of the test font's boxes.
Future<void> loadFonts() async {
  final manifest = jsonDecode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<Object?>;
  for (final family in manifest.cast<Map<String, Object?>>()) {
    final loader = FontLoader(family['family']! as String);
    for (final font in (family['fonts']! as List).cast<Map>()) {
      loader.addFont(rootBundle.load(Uri.decodeFull(font['asset'] as String)));
    }
    await loader.load();
  }
}

final _root = GlobalKey();

/// Pumps [child] on a canvas of [size] logical pixels.
Future<void> render(
  WidgetTester tester,
  Size size,
  double pixelRatio,
  Widget child,
) async {
  tester.view
    ..physicalSize = size * pixelRatio
    ..devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: _root, child: child));
}

/// Writes the canvas as an opaque PNG: App Store Connect refuses alpha.
Future<void> save(WidgetTester tester, String path) async {
  final boundary =
      _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final rgba = await image.toByteData();
    final opaque = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba!.buffer,
      numChannels: 4,
    ).convert(numChannels: 3);
    final file = File(path)..parent.createSync(recursive: true);
    await file.writeAsBytes(img.encodePng(opaque));
  });
}
