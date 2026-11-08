import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/pressable.dart';

void main() {
  const key = Key('target');

  /// A 200 px square that counts its taps in [onTap], with less motion when
  /// [reduced].
  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onTap,
    bool enabled = true,
    bool reduced = false,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Center(
        child: Pressable(
          onTap: enabled ? onTap ?? () {} : null,
          child: const SizedBox.square(key: key, dimension: 200),
        ),
      ),
    ),
  );

  double width(WidgetTester tester) => tester.getRect(find.byKey(key)).width;

  testWidgets('a control shrinks under a finger and comes back', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, onTap: () => taps++);

    final finger = await tester.startGesture(tester.getCenter(find.byKey(key)));
    await tester.pumpAndSettle();
    final held = width(tester);
    await finger.up();
    await tester.pumpAndSettle();

    expect(held, moreOrLessEquals(194));
    expect(width(tester), 200);
    expect(taps, 1);
  });

  testWidgets('a quick tap still shows the press', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(key));
    var smallest = width(tester);
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (width(tester) < smallest) smallest = width(tester);
    }

    expect(smallest, moreOrLessEquals(194, epsilon: 1));
    expect(width(tester), 200);
  });

  for (final (name, enabled, reduced) in [
    ('a disabled control', false, false),
    ('a control under reduced motion', true, true),
  ]) {
    testWidgets('$name keeps its size under a finger', (tester) async {
      await pump(tester, enabled: enabled, reduced: reduced);

      final finger = await tester.startGesture(
        tester.getCenter(find.byKey(key)),
      );
      await tester.pumpAndSettle();
      expect(width(tester), 200);
      await finger.up();
    });
  }

  testWidgets('a control inside another answers alone', (tester) async {
    const inner = Key('inner');
    await tester.pumpWidget(
      Center(
        child: Pressable(
          onTap: () {},
          child: SizedBox.square(
            key: key,
            dimension: 200,
            child: Center(
              child: Pressable(
                onTap: () {},
                child: const SizedBox.square(key: inner, dimension: 100),
              ),
            ),
          ),
        ),
      ),
    );

    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(inner)),
    );
    await tester.pumpAndSettle();

    expect(width(tester), 200);
    expect(tester.getRect(find.byKey(inner)).width, moreOrLessEquals(97));
    await finger.up();
  });
}
