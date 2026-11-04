import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/settings/language/brand_language.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';

void main() {
  group('as the system', () {
    test('a Russian system gets Russian', () {
      final locale = BrandLanguage.of(
        LanguageCode.system,
        system: const Locale('ru', 'KZ'),
      );
      expect(locale, const Locale('ru'));
    });

    test('any other system gets English, even one upstream translates', () {
      for (final system in const [Locale('de'), Locale('fa'), Locale('zh')]) {
        expect(
          BrandLanguage.of(LanguageCode.system, system: system),
          const Locale('en'),
        );
      }
    });
  });

  test('a chosen language wins over the system', () {
    expect(
      BrandLanguage.of(LanguageCode.en, system: const Locale('ru')),
      const Locale('en'),
    );
    expect(
      BrandLanguage.of(LanguageCode.ru, system: const Locale('en')),
      const Locale('ru'),
    );
  });
}
