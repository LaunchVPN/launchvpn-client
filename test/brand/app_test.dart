import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/brand/app.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('screens and text outside them speak the same language', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    const probe = ValueKey('probe');
    final bus = AppEventBus();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const SizedBox(key: probe),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(BrandApp(routerConfig: router, eventBus: bus));

    for (final (system, choice, expected) in const [
      (Locale('ru', 'RU'), LanguageCode.system, 'ru'),
      (Locale('de'), LanguageCode.system, 'en'),
      (Locale('fa', 'IR'), LanguageCode.fa, 'en'),
      (Locale('en'), LanguageCode.ru, 'ru'),
      (Locale('ru'), LanguageCode.en, 'en'),
    ]) {
      tester.platformDispatcher
        ..localeTestValue = system
        ..localesTestValue = [system];
      await tester.runAsync(() => bus.updateLanguageCode(choice));
      await tester.pumpAndSettle();

      final context = tester.element(find.byKey(probe));
      expect(AppLocalizations.of(context)!.localeName, expected);
      expect(appLocalizationsNoContext().localeName, expected);
    }
  });
}
