import 'package:flutter/widgets.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

/// LaunchVPN speaks Russian and English only, of upstream's languages. The
/// choice is upstream's saved [LanguageCode]; this decides what it shows.
abstract final class BrandLanguage {
  static const russian = Locale('ru');

  /// In the order the language screen lists them.
  static const options = [
    LanguageCode.system,
    LanguageCode.ru,
    LanguageCode.en,
  ];

  static const supportedLocales = [AppLocalePolicy.english, russian];

  /// Russian on a Russian system and English on any other. Upstream's other
  /// languages, never offered here, count as the system.
  static Locale of(LanguageCode choice, {Locale? system}) =>
      chosen(choice) ??
      forSystem(system ?? WidgetsBinding.instance.platformDispatcher.locale);

  /// Null when [choice] follows the system.
  static Locale? chosen(LanguageCode choice) => switch (choice) {
    LanguageCode.ru => russian,
    LanguageCode.en => AppLocalePolicy.english,
    _ => null,
  };

  /// What "Same as system" shows on [system].
  static Locale forSystem(Locale? system) =>
      system?.languageCode == russian.languageCode
      ? russian
      : AppLocalePolicy.english;

  /// The App's language now, for text shown outside a screen.
  static Locale get current => of(AppEventBus.instance.state.languageCode);
}
