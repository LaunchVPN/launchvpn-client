import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/toggle.dart';
import 'package:onexray/brand/mark.dart';

void main() {
  /// The toggle in [state], with less motion when [reduced].
  Future<void> pump(
    WidgetTester tester,
    ConnectToggleState state, {
    bool reduced = false,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ConnectToggle(state: state, label: 'VPN', onPressed: () {}),
        ),
      ),
    ),
  );

  Color track(WidgetTester tester) =>
      (tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: find.byType(ConnectToggle),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration)
          .color!;

  double knob(WidgetTester tester) =>
      tester.getCenter(find.byType(LaunchMark)).dx;

  /// The track's colors over a second and a half.
  Future<Set<Color>> watchTrack(WidgetTester tester) async {
    final colors = {track(tester)};
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      colors.add(track(tester));
    }
    return colors;
  }

  testWidgets('the track pulses while the connection changes', (tester) async {
    await pump(tester, ConnectToggleState.transitioning);
    await tester.pump(const Duration(seconds: 1));

    expect((await watchTrack(tester)).length, greaterThan(5));

    await pump(tester, ConnectToggleState.on);
    await tester.pumpAndSettle();
    expect(await watchTrack(tester), hasLength(1));
  });

  testWidgets('with less motion the track holds still', (tester) async {
    await pump(tester, ConnectToggleState.transitioning, reduced: true);
    await tester.pump();

    expect(await watchTrack(tester), hasLength(1));
  });

  testWidgets('the knob overshoots a little as it arrives on', (tester) async {
    await pump(tester, ConnectToggleState.on);
    final rest = knob(tester);
    await pump(tester, ConnectToggleState.transitioning);
    await tester.pump(const Duration(seconds: 1));

    await pump(tester, ConnectToggleState.on);
    var furthest = knob(tester);
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (knob(tester) > furthest) furthest = knob(tester);
    }

    expect(furthest, greaterThan(rest + 1));
    expect(furthest, lessThan(rest + 8));
    expect(knob(tester), moreOrLessEquals(rest));
  });
}
