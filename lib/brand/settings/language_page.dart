import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/top_bar.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/brand_language.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';

/// Lists the languages and applies a tap at once, so the screen itself
/// switches to the new language.
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key, required this.onSelected});

  final ValueChanged<LanguageCode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BrandTheme.statusBar,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              BrandTopBar(title: l.settingsLanguage),
              Expanded(
                child: BlocBuilder<AppEventBus, AppEventBusState>(
                  buildWhen: (a, b) => a.languageCode != b.languageCode,
                  builder: (context, state) {
                    final current = BrandLanguage.chosen(state.languageCode);
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        BrandSpacing.page,
                        0,
                        BrandSpacing.page,
                        MediaQuery.paddingOf(context).bottom + 20,
                      ),
                      children: [
                        SettingsCard(
                          children: [
                            for (final option in BrandLanguage.options)
                              _option(
                                l,
                                option,
                                selected:
                                    BrandLanguage.chosen(option) == current,
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(
    AppLocalizations l,
    LanguageCode option, {
    required bool selected,
  }) => SettingsRow(
    title: languageLabel(l, option),
    subtitle: option == LanguageCode.system ? _systemNow(l) : null,
    selected: selected,
    onTap: () => onSelected(option),
    trailing: selected
        ? const Icon(LucideIcons.check, size: 18, color: BrandColors.accent)
        : null,
  );

  static String _systemNow(AppLocalizations l) =>
      BrandLanguage.of(LanguageCode.system) == BrandLanguage.russian
      ? l.settingsLanguageNowRussian
      : l.settingsLanguageNowEnglish;
}

/// Each language under its own name, which no translation changes.
String languageLabel(AppLocalizations l, LanguageCode choice) =>
    switch (choice) {
      LanguageCode.ru => 'Русский',
      LanguageCode.en => 'English',
      // Upstream's other languages count as the system.
      _ => l.settingsLanguageSystem,
    };
