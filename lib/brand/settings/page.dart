import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/settings/controller.dart';
import 'package:onexray/brand/settings/language_page.dart';
import 'package:onexray/brand/settings/preset_page.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/subscription/renewal_reminders.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';

/// The Settings tab. Its other rows arrive with their features.
class BrandSettingsPage extends StatefulWidget {
  const BrandSettingsPage({
    super.key,
    required this.controller,
    this.reminders,
  });

  final HomeController controller;

  /// The App's own when null.
  final RenewalReminders? reminders;

  @override
  State<BrandSettingsPage> createState() => _BrandSettingsPageState();
}

class _BrandSettingsPageState extends State<BrandSettingsPage> {
  late final _settings = SettingsController(reminders: widget.reminders);

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
    unawaited(_settings.initialize());
    // Notifications may have been allowed in the system settings meanwhile.
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_settings.readRenewalReminders()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
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

  Future<void> _openLanguages() =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) => LanguagePage(onSelected: _settings.setLanguage),
        ),
      );

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
              _SectionLabel(l.settingsConnection),
              SettingsCard(
                children: [
                  BlocBuilder<HomeController, HomeState>(
                    bloc: widget.controller,
                    builder: (context, state) => SettingsLinkRow(
                      icon: LucideIcons.route,
                      title: l.settingsPresets,
                      value: _presetLabel(l, state.preset),
                      onTap: _openPresets,
                    ),
                  ),
                  BlocBuilder<SettingsController, SettingsState>(
                    bloc: _settings,
                    buildWhen: (a, b) => a.connectOnLaunch != b.connectOnLaunch,
                    builder: (context, state) => SettingsSwitchRow(
                      icon: LucideIcons.zap,
                      title: l.settingsConnectOnLaunch,
                      value: state.connectOnLaunch,
                      onChanged: _settings.setConnectOnLaunch,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionLabel(l.settingsApp),
              SettingsCard(
                children: [
                  BlocBuilder<AppEventBus, AppEventBusState>(
                    buildWhen: (a, b) => a.languageCode != b.languageCode,
                    builder: (context, state) => SettingsLinkRow(
                      icon: LucideIcons.globe,
                      title: l.settingsLanguage,
                      value: languageLabel(l, state.languageCode),
                      onTap: _openLanguages,
                    ),
                  ),
                  BlocBuilder<SettingsController, SettingsState>(
                    bloc: _settings,
                    buildWhen: (a, b) =>
                        a.renewalReminders != b.renewalReminders,
                    builder: (context, state) => SettingsSwitchRow(
                      icon: LucideIcons.bell,
                      title: l.settingsRenewalReminders,
                      subtitle: l.settingsRenewalRemindersHint,
                      value: state.renewalReminders,
                      onChanged: _settings.setRenewalReminders,
                    ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 8),
    child: Text(text.toUpperCase(), style: BrandText.sectionLabel),
  );
}

/// Null for a preset this screen does not offer, or before it is read.
String? _presetLabel(AppLocalizations l, TrafficMode? preset) =>
    switch (preset) {
      TrafficMode.smart => l.homePresetSmart,
      TrafficMode.allVpn => l.homePresetAllVpn,
      TrafficMode.custom || null => null,
    };
