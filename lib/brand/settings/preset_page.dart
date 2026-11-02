import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/top_bar.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/connect/settings.dart';

/// Lists the presets and pops with the one the user taps. Settings applies the
/// choice, so a reconnect that outlives this screen still reports to it.
class PresetPage extends StatelessWidget {
  const PresetPage({super.key, required this.controller});

  final HomeController controller;

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
              BrandTopBar(title: l.settingsPresets),
              Expanded(
                child: BlocBuilder<HomeController, HomeState>(
                  bloc: controller,
                  builder: (context, state) {
                    Widget row(
                      TrafficMode preset,
                      IconData icon,
                      String title,
                      String hint,
                    ) {
                      final selected = preset == state.preset;
                      final enabled = state.canChangeConnection;
                      return Opacity(
                        opacity: enabled || selected ? 1 : 0.5,
                        child: SettingsRow(
                          icon: icon,
                          title: title,
                          subtitle: hint,
                          selected: selected,
                          onTap: enabled
                              ? () => Navigator.of(context).pop(preset)
                              : null,
                          trailing: selected
                              ? const Icon(
                                  LucideIcons.check,
                                  size: 18,
                                  color: BrandColors.accent,
                                )
                              : null,
                        ),
                      );
                    }

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
                            row(
                              TrafficMode.smart,
                              LucideIcons.route,
                              l.homePresetSmart,
                              l.settingsPresetSmartHint,
                            ),
                            row(
                              TrafficMode.allVpn,
                              LucideIcons.shield,
                              l.homePresetAllVpn,
                              l.settingsPresetAllVpnHint,
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                          child: Text(
                            l.settingsPresetFootnote,
                            style: BrandText.caption,
                          ),
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
}
