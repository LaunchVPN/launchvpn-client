import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/l10n/localizations/app_localizations_en.dart';
import 'package:onexray/service/settings/language/brand_language.dart';

AppLocalizations appLocalizationsNoContext() {
  try {
    return lookupAppLocalizations(BrandLanguage.current);
  } catch (_) {
    return AppLocalizationsEn();
  }
}
