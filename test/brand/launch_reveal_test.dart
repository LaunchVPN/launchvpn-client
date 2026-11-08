import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/launch_reveal.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/theme.dart';

import '../support/opacity.dart';

void main() {
  const landingKey = Key('landing');

  /// A page whose header holds the landing, and a counter that shows whether
  /// the page kept its state.
  Widget page({bool landing = true}) => Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (landing)
              const LaunchMarkLanding(
                key: landingKey,
                child: LaunchMark.logo(color: BrandColors.accent),
              ),
            const _Counter(),
          ],
        ),
      ),
    ),
  );

  Future<void> pump(WidgetTester tester, Widget? child) =>
      tester.pumpWidget(MaterialApp(home: LaunchReveal(child: child)));

  double landingOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find.descendant(
          of: find.byKey(landingKey),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;

  testWidgets('shows the mark, and the spinner only after a second', (
    tester,
  ) async {
    await pump(tester, null);

    expect(find.byType(LaunchMark), findsOneWidget);
    final spinner = find.ancestor(
      of: find.byType(CircularProgressIndicator),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(spinner).opacity, 0);

    await tester.pump(LaunchReveal.spinnerDelay);
    expect(tester.widget<AnimatedOpacity>(spinner).opacity, 1);
  });

  testWidgets('the mark flies into the landing, which then shows', (
    tester,
  ) async {
    await pump(tester, null);
    await pump(tester, page());
    await tester.pump();
    await tester.pump(LaunchReveal.duration ~/ 2);

    expect(find.byType(LaunchMark), findsNWidgets(2));
    expect(landingOpacity(tester), 0);

    await tester.pumpAndSettle();
    expect(find.byType(LaunchMark), findsOneWidget);
    expect(landingOpacity(tester), 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the page keeps its state once the mark is gone', (tester) async {
    await pump(tester, page());
    await tester.pump();
    await tester.pump(LaunchReveal.duration ~/ 2);
    await tester.tap(find.text('0'));
    await tester.pumpAndSettle();

    expect(find.byType(LaunchMark), findsOneWidget, reason: 'mark is gone');
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('without a landing the mark fades where it is', (tester) async {
    await pump(tester, null);
    await pump(tester, page(landing: false));
    await tester.pumpAndSettle();

    expect(find.byType(LaunchMark), findsNothing);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('a retry brings the mark back, then reveals again', (
    tester,
  ) async {
    await pump(tester, page(landing: false));
    await tester.pumpAndSettle();
    expect(find.byType(LaunchMark), findsNothing);

    await pump(tester, null);
    expect(find.byType(LaunchMark), findsOneWidget);
    expect(find.text('0'), findsNothing);

    await pump(tester, page());
    await tester.pumpAndSettle();
    expect(find.byType(LaunchMark), findsOneWidget);
    expect(landingOpacity(tester), 1);
  });

  testWidgets('a page that changes mid-flight still gets the mark', (
    tester,
  ) async {
    await pump(tester, null);
    await pump(tester, page(landing: false));
    await tester.pump();
    await tester.pump(LaunchReveal.duration ~/ 3);
    await pump(tester, page());
    await tester.pumpAndSettle();

    expect(find.byType(LaunchMark), findsOneWidget);
    expect(landingOpacity(tester), 1);
  });

  group('a later page', () {
    /// Another kind of page than [page], as the tabs are after «Вход».
    Widget other(String text, {Key? key}) =>
        ColoredBox(key: key, color: BrandColors.bg, child: Text(text));

    testWidgets('fades in over the one it replaces, which stays as it was', (
      tester,
    ) async {
      await pump(tester, page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('0'));
      await tester.pump();

      await pump(tester, other('tabs'));
      await tester.pump(LaunchReveal.duration ~/ 2);

      expect(shownOpacity(tester, find.text('1')), 1);
      expect(shownOpacity(tester, find.text('tabs')), inExclusiveRange(0, 1));
      expect(find.text('1').hitTestable(), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('1'), findsNothing);
      expect(shownOpacity(tester, find.text('tabs')), 1);
    });

    testWidgets('that comes back mid-fade shows once', (tester) async {
      final tabs = GlobalKey();
      await pump(tester, other('tabs', key: tabs));
      await tester.pumpAndSettle();

      await pump(tester, page());
      await tester.pump(LaunchReveal.duration ~/ 3);
      await pump(tester, other('tabs again', key: tabs));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('tabs again'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('with animations off shows at once', (tester) async {
      Future<void> pumpStill(Widget child) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: LaunchReveal(child: child),
          ),
        ),
      );
      await pumpStill(page());
      await tester.pump();
      await tester.pump();

      await pumpStill(other('tabs'));
      await tester.pump();

      expect(find.text('0'), findsNothing);
      expect(shownOpacity(tester, find.text('tabs')), 1);
    });
  });

  testWidgets('with animations off the page shows at once', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LaunchReveal(child: page()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(LaunchMark), findsOneWidget);
    expect(landingOpacity(tester), 1);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => _taps++),
    child: Text('$_taps'),
  );
}
