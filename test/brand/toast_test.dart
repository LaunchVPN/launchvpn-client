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
  }) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Widget screen = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showBrandToast(context, message, kind: kind),
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
    await tester.pumpAndSettle();
  }

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

  testWidgets('a toast moves above the tab bar when the tabs appear', (
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
    await tester.pumpAndSettle();

    expect(find.text('Готово'), findsOneWidget);
    expect(
      tester.getRect(find.byType(ShadToast)).bottom,
      lessThanOrEqualTo(2532 / 3 - 80),
    );
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
