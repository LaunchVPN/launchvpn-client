import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/settings/controller.dart';
import 'package:onexray/brand/settings/preset_page.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch;

/// The Settings tab. Its other rows arrive with their features.
class BrandSettingsPage extends StatefulWidget {
  const BrandSettingsPage({super.key, required this.controller});

  final HomeController controller;

  @override
  State<BrandSettingsPage> createState() => _BrandSettingsPageState();
}

class _BrandSettingsPageState extends State<BrandSettingsPage> {
  final _settings = SettingsController();

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
    unawaited(_settings.initialize());
  }

  @override
  void dispose() {
    unawaited(_settings.close());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) =>
      runConnectionAction(context, widget.controller.coordinator, action);

  // Above the tab bar, as the mockup has it.
  Future<void> _openPresets() async {
    final chosen = await Navigator.of(context, rootNavigator: true)
        .push<TrafficMode>(
          MaterialPageRoute(
            builder: (_) => PresetPage(controller: widget.controller),
          ),
        );
    if (chosen != null && mounted) {
      await widget.controller.selectPreset(chosen, _run);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BrandTheme.statusBar,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              BrandSpacing.page,
              8,
              BrandSpacing.page,
              20,
            ),
            children: [
              Text(l.prototypeSettings, style: BrandText.screenTitle),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 8),
                child: Text(
                  l.settingsConnection.toUpperCase(),
                  style: BrandText.sectionLabel,
                ),
              ),
              SettingsCard(
                children: [
                  BlocBuilder<HomeController, HomeState>(
                    bloc: widget.controller,
                    builder: (context, state) {
                      final preset = _presetLabel(l, state.preset);
                      return SettingsRow(
                        icon: LucideIcons.route,
                        title: l.settingsPresets,
                        value: preset,
                        onTap: _openPresets,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (preset != null) ...[
                              Text(preset, style: BrandText.caption),
                              const SizedBox(width: 12),
                            ],
                            const Icon(
                              LucideIcons.chevronRight,
                              size: 18,
                              color: BrandColors.muted,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  BlocBuilder<SettingsController, SettingsState>(
                    bloc: _settings,
                    builder: (context, state) {
                      final enabled = state.connectOnLaunch;
                      return SettingsRow(
                        icon: LucideIcons.zap,
                        title: l.settingsConnectOnLaunch,
                        toggled: enabled ?? false,
                        onTap: enabled == null
                            ? null
                            : () => _settings.setConnectOnLaunch(!enabled),
                        // The whole row is the control.
                        trailing: IgnorePointer(
                          child: ShadSwitch(
                            value: enabled ?? false,
                            width: 51,
                            height: 31,
                            margin: 2,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Null for a preset this screen does not offer, or before it is read.
String? _presetLabel(AppLocalizations l, TrafficMode? preset) =>
    switch (preset) {
      TrafficMode.smart => l.homePresetSmart,
      TrafficMode.allVpn => l.homePresetAllVpn,
      TrafficMode.custom || null => null,
    };
