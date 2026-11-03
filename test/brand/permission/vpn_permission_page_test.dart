import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/permission/vpn_permission_page.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';

void main() {
  /// Opens the screen from a button and returns what it answered, or null
  /// while it is still open.
  Future<bool? Function()> open(WidgetTester tester, {double scale = 1}) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: BrandTheme.material(),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                answer = await VpnPermissionPage.show(context),
            child: const Text('connect'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('connect'));
    await tester.pumpAndSettle();
    return () => answer;
  }

  testWidgets('«Продолжить» lets the system prompt follow', (tester) async {
    final answer = await open(tester);

    expect(find.text('Разрешите VPN'), findsOneWidget);
    expect(find.text('Без логов посещённых сайтов'), findsOneWidget);
    expect(find.text('Отключается одной кнопкой'), findsOneWidget);

    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    expect(answer(), isTrue);
    expect(find.text('Разрешите VPN'), findsNothing);
  });

  testWidgets('«Не сейчас» and the back gesture decline', (tester) async {
    var answer = await open(tester);
    await tester.tap(find.text('Не сейчас'));
    await tester.pumpAndSettle();
    expect(answer(), isFalse);

    answer = await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(answer(), isFalse);
    expect(find.text('Разрешите VPN'), findsNothing);
  });

  testWidgets('a small screen with large text scrolls to the buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await open(tester, scale: 1.6);

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Не сейчас'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не сейчас'));
    await tester.pumpAndSettle();
    expect(find.text('Разрешите VPN'), findsNothing);
  });
}
