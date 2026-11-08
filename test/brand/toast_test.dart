import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/icon_tile.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/toast.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  /// A phone screen whose button shows [message] as [kind], inside a
  /// [ToastArea] of [bottom] when given.
  Future<void> show(
    WidgetTester tester,
    String message, {
    ToastKind kind = ToastKind.info,
    double? bottom,
    double? top,
    bool settle = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Widget screen = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () =>
                showBrandToast(context, message, kind: kind, top: top),
            child: const Text('show'),
          ),
        ),
      ),
    );
    if (bottom != null) screen = ToastArea(bottom: bottom, child: screen);
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.material(),
        builder: (context, child) => ShadTheme(
          data: BrandTheme.shad(TextScaler.noScaling),
          child: ShadToaster(child: child!),
        ),
        home: screen,
      ),
    );
    await tester.tap(find.text('show'));
    if (settle) await tester.pumpAndSettle();
  }

  /// How opaque the toast shows through every fade above it.
  double opacity(WidgetTester tester) {
    if (find.byType(ShadToast).evaluate().isEmpty) return 0;
    final above = find.ancestor(
      of: find.byType(ShadToast),
      matching: find.byWidgetPredicate(
        (widget) => widget is FadeTransition || widget is Opacity,
      ),
    );
    return tester
        .widgetList(above)
        .fold(
          1.0,
          (shown, widget) =>
              shown *
              switch (widget) {
                FadeTransition(:final opacity) => opacity.value,
                Opacity(:final opacity) => opacity,
                _ => 1.0,
              },
        );
  }

  Rect toast(WidgetTester tester) => tester.getRect(find.byType(ShadToast));

  testWidgets('a toast rises into place as it fades in', (tester) async {
    await show(tester, 'Готово', settle: false);
    await tester.pump();
    await tester.pump();
    final start = toast(tester);
    final faded = opacity(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final late = opacity(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(faded, lessThan(0.05));
    expect(late, lessThan(1));
    expect(opacity(tester), 1);
    final rest = toast(tester);
    await tester.pumpAndSettle();
    expect(toast(tester), rest);
    expect(start.bottom - rest.bottom, moreOrLessEquals(8));
  });

  testWidgets('a toast at the top drops into place', (tester) async {
    await show(tester, 'Готово', top: 56, settle: false);
    await tester.pump();
    final start = toast(tester);
    await tester.pumpAndSettle();

    expect(toast(tester).top - start.top, moreOrLessEquals(8));
  });

  testWidgets('a toast fades out in 350 ms once read', (tester) async {
    await show(tester, 'Готово');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 340));
    expect(opacity(tester), allOf(greaterThan(0), lessThan(1)));

    await tester.pump(const Duration(milliseconds: 10));
    expect(opacity(tester), lessThan(0.01));
    await tester.pumpAndSettle();
    expect(find.byType(ShadToast), findsNothing);
  });

  testWidgets('each kind shows its icon', (tester) async {
    for (final (kind, icon) in [
      (ToastKind.success, LucideIcons.check),
      (ToastKind.error, LucideIcons.triangleAlert),
      (ToastKind.info, LucideIcons.info),
    ]) {
      await show(tester, 'Готово', kind: kind);
      expect(find.byIcon(icon), findsOneWidget);
    }
  });

  testWidgets('on a tab, the toast clears the tab bar', (tester) async {
    await show(tester, 'Готово', bottom: 80);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byType(ShadToast)).bottom,
      lessThanOrEqualTo(screen.height - 80),
    );
  });

  testWidgets('one line centres on the tile', (tester) async {
    await show(tester, 'Готово');

    final tile = tester.getRect(find.byType(IconTile));
    final text = tester.getRect(find.text('Готово'));
    expect(text.center.dy, moreOrLessEquals(tile.center.dy, epsilon: 1));
  });

  testWidgets('a larger text size still centres one line on the tile', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await show(tester, 'Готово');

    final tile = tester.getRect(find.byType(IconTile));
    final text = tester.getRect(find.text('Готово'));
    expect(text.center.dy, moreOrLessEquals(tile.center.dy, epsilon: 1));
  });

  testWidgets('a toast moves above the tab bar without showing again', (
    tester,
  ) async {
    final tabs = ValueNotifier(false);
    addTearDown(tabs.dispose);
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.material(),
        builder: (context, child) => ShadTheme(
          data: BrandTheme.shad(TextScaler.noScaling),
          child: ShadToaster(child: child!),
        ),
        home: ValueListenableBuilder(
          valueListenable: tabs,
          builder: (context, shown, _) {
            final screen = Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showBrandToast(context, 'Готово'),
                    child: const Text('show'),
                  ),
                ),
              ),
            );
            return shown ? ToastArea(bottom: 80, child: screen) : screen;
          },
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    tabs.value = true;
    final bottoms = [toast(tester).bottom];
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      bottoms.add(toast(tester).bottom);
      expect(opacity(tester), 1, reason: 'the entrance does not play again');
    }

    for (var frame = 1; frame < bottoms.length; frame++) {
      expect(bottoms[frame], lessThanOrEqualTo(bottoms[frame - 1]));
    }
    expect(bottoms.last, lessThanOrEqualTo(2532 / 3 - 80));
  });

  testWidgets('more lines start at the tile', (tester) async {
    const long =
        'Если приложение сломается, оно пришлёт нам отчёт без ссылок, '
        'адресов и email. Выключить можно в настройках.';
    await show(tester, long);

    final tile = tester.getRect(find.byType(IconTile));
    final text = tester.getRect(find.text(long));
    expect(text.top, lessThan(tile.top));
    expect(text.height, greaterThan(tile.height));
  });
}
