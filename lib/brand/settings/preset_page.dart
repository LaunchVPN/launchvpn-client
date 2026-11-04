import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/top_bar.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/connect/preset.dart';

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
                    Widget row(ConnectionPreset preset) {
                      final selected = preset == state.preset;
                      final enabled = state.canChangeConnection;
                      return Opacity(
                        opacity: enabled || selected ? 1 : 0.5,
                        child: SettingsRow(
                          icon: _icons[preset],
                          title: presetLabel(l, preset),
                          subtitle: _hint(l, preset),
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
                            for (final preset in controller.presets)
                              row(preset),
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

String presetLabel(AppLocalizations l, ConnectionPreset preset) =>
    switch (preset) {
      ConnectionPreset.smart => l.homePresetSmart,
      ConnectionPreset.allVpn => l.homePresetAllVpn,
      ConnectionPreset.apps => l.homePresetApps,
    };

String _hint(AppLocalizations l, ConnectionPreset preset) => switch (preset) {
  ConnectionPreset.smart => l.settingsPresetSmartHint,
  ConnectionPreset.allVpn => l.settingsPresetAllVpnHint,
  ConnectionPreset.apps => l.settingsPresetAppsHint,
};

const _icons = {
  ConnectionPreset.smart: LucideIcons.route,
  ConnectionPreset.allVpn: LucideIcons.shield,
  ConnectionPreset.apps: LucideIcons.layoutGrid,
};
