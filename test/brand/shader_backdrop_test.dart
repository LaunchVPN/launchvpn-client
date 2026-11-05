import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/shader_backdrop.dart';
import 'package:onexray/brand/theme.dart';

void main() {
  late FragmentProgram program;

  setUpAll(() async {
    program = await FragmentProgram.fromAsset('shaders/dark_veil.frag');
  });

  Future<void> pumpBackdrop(
    WidgetTester tester, {
    bool disableAnimations = false,
    bool tickers = true,
    double devicePixelRatio = 1,
    Future<FragmentProgram> Function()? loadProgram,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          disableAnimations: disableAnimations,
          devicePixelRatio: devicePixelRatio,
        ),
        child: TickerMode(
          enabled: tickers,
          child: ShaderBackdrop(
            loadProgram: loadProgram ?? () async => program,
            child: const Text('form', textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The color the screen shows near its top left corner.
  Future<Color> cornerColor(WidgetTester tester) async {
    final bytes = await tester.runAsync(() async {
      final image = await captureImage(tester.element(find.text('form')));
      return image.toByteData();
    });
    return Color.fromARGB(
      bytes!.getUint8(3),
      bytes.getUint8(0),
      bytes.getUint8(1),
      bytes.getUint8(2),
    );
  }

  testWidgets('animates when motion is allowed', (tester) async {
    await pumpBackdrop(tester);

    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(find.text('form'), findsOneWidget);
  });

  testWidgets('holds a still frame under reduced motion', (tester) async {
    await pumpBackdrop(tester, disableAnimations: true);

    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await cornerColor(tester), isNot(BrandBackdrop.base));
  });

  testWidgets('stops while its screen is hidden', (tester) async {
    await pumpBackdrop(tester, tickers: false);

    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await pumpBackdrop(tester);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('stops while the app is in the background', (tester) async {
    await pumpBackdrop(tester);
    await tester.pump(const Duration(seconds: 1));
    final shown = await cornerColor(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(hours: 1));
    expect(await cornerColor(tester), shown);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  RenderObject veil(WidgetTester tester) => tester.renderObject(
    find.descendant(
      of: find.byType(ShaderBackdrop),
      matching: find.byType(CustomPaint),
    ),
  );

  testWidgets('renders at most 1.5 pixels per point, scaled up to a denser '
      'screen', (tester) async {
    await pumpBackdrop(tester, disableAnimations: true, devicePixelRatio: 3);

    expect(
      veil(tester),
      paints..drawImageRect(
        source: const Rect.fromLTWH(0, 0, 1200, 900),
        destination: const Rect.fromLTWH(0, 0, 800, 600),
      ),
    );
  });

  testWidgets('draws straight onto a screen within the cap', (tester) async {
    await pumpBackdrop(tester, disableAnimations: true, devicePixelRatio: 1.5);

    expect(
      veil(tester),
      paints..rect(rect: const Rect.fromLTWH(0, 0, 800, 600)),
    );
    expect(veil(tester), isNot(paints..drawImageRect()));
  });

  testWidgets('stays plain when the shader fails to load', (tester) async {
    await pumpBackdrop(
      tester,
      loadProgram: () => Future.error(Exception('no shader')),
    );

    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await cornerColor(tester), BrandBackdrop.base);
    expect(find.text('form'), findsOneWidget);
  });
}
