import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/pressable.dart';

void main() {
  const key = Key('target');

  /// A 200 px square that taps into [taps], with less motion when [reduced].
  Future<void> pump(
    WidgetTester tester, {
    required List<int> taps,
    bool enabled = true,
    bool reduced = false,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Center(
        child: Pressable(
          onTap: enabled ? () => taps.add(1) : null,
          child: const SizedBox.square(key: key, dimension: 200),
        ),
      ),
    ),
  );

  double width(WidgetTester tester) => tester.getRect(find.byKey(key)).width;

  testWidgets('a control shrinks under a finger and comes back', (
    tester,
  ) async {
    final taps = <int>[];
    await pump(tester, taps: taps);

    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(key)),
    );
    await tester.pumpAndSettle();
    final held = width(tester);
    await finger.up();
    await tester.pumpAndSettle();

    expect(held, moreOrLessEquals(194));
    expect(width(tester), 200);
    expect(taps, hasLength(1));
  });

  testWidgets('a quick tap still shows the press', (tester) async {
    final taps = <int>[];
    await pump(tester, taps: taps);

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
      await pump(tester, taps: [], enabled: enabled, reduced: reduced);

      final finger = await tester.startGesture(
        tester.getCenter(find.byKey(key)),
      );
      await tester.pumpAndSettle();
      expect(width(tester), 200);
      await finger.up();
    });
  }
}
