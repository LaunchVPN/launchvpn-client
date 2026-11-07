import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/section_label.dart';
import 'package:onexray/brand/settings/about_page.dart';
import 'package:onexray/brand/settings/controller.dart';
import 'package:onexray/brand/settings/language_page.dart';
import 'package:onexray/brand/settings/preset_page.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/settings/vpn_apps_page.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/service/connect/preset.dart';
import 'package:onexray/service/crash_reports/service.dart';
import 'package:onexray/service/servers/subscription/renewal_reminders.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';

/// The Settings tab. Its other rows arrive with their features.
class BrandSettingsPage extends StatefulWidget {
  const BrandSettingsPage({
    super.key,
    required this.controller,
    this.reminders,
    this.crashReports,
  });

  final HomeController controller;

  /// The App's own when null.
  final RenewalReminders? reminders;

  /// The App's own when null.
  final CrashReports? crashReports;

  @override
  State<BrandSettingsPage> createState() => _BrandSettingsPageState();
}

class _BrandSettingsPageState extends State<BrandSettingsPage> {
  late final _settings = SettingsController(
    reminders: widget.reminders,
    crashReports: widget.crashReports,
  );

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
        .push<ConnectionPreset>(
          MaterialPageRoute(
            builder: (_) => PresetPage(controller: widget.controller),
          ),
        );
    if (chosen != null && mounted) {
      await choosePreset(context, widget.controller, chosen, _run);
    }
  }

  Future<void> _openLanguages() =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) => LanguagePage(onSelected: _settings.setLanguage),
        ),
      );

  Future<void> _openAbout() =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              AboutPage(settings: _settings, home: widget.controller),
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
              SectionLabel(l.settingsConnection),
              SettingsCard(
                children: [
                  BlocBuilder<HomeController, HomeState>(
                    bloc: widget.controller,
                    builder: (context, state) => SettingsLinkRow(
                      icon: LucideIcons.route,
                      title: l.settingsPresets,
                      value: switch (state.preset) {
                        final preset? => presetLabel(l, preset),
                        null => null,
                      },
                      onTap: _openPresets,
                    ),
                  ),
                  if (widget.controller.presets.contains(ConnectionPreset.apps))
                    BlocBuilder<HomeController, HomeState>(
                      bloc: widget.controller,
                      buildWhen: (a, b) =>
                          a.vpnApps != b.vpnApps ||
                          a.canChangeConnection != b.canChangeConnection,
                      builder: (context, state) => SettingsLinkRow(
                        icon: LucideIcons.layoutGrid,
                        title: l.settingsVpnApps,
                        subtitle: l.settingsVpnAppsHint,
                        value: state.vpnApps.isEmpty
                            ? null
                            : '${state.vpnApps.length}',
                        // A list saved mid-command would be lost.
                        onTap: state.canChangeConnection
                            ? () =>
                                  editVpnApps(context, widget.controller, _run)
                            : null,
                      ),
                    ),
                  if (widget.controller.offersKeepVpnOn)
                    BlocBuilder<HomeController, HomeState>(
                      bloc: widget.controller,
                      buildWhen: (a, b) =>
                          a.keepVpnOn != b.keepVpnOn ||
                          a.canChangeConnection != b.canChangeConnection,
                      builder: (context, state) => SettingsSwitchRow(
                        icon: LucideIcons.shieldCheck,
                        title: l.settingsKeepVpnOn,
                        subtitle: l.settingsKeepVpnOnHint,
                        value: state.keepVpnOn,
                        // A value saved mid-command would be lost.
                        onChanged: state.canChangeConnection
                            ? (value) =>
                                  widget.controller.saveKeepVpnOn(value, _run)
                            : null,
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
              SectionLabel(l.settingsApp),
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
                  BlocBuilder<SettingsController, SettingsState>(
                    bloc: _settings,
                    buildWhen: (a, b) => a.crashReports != b.crashReports,
                    builder: (context, state) => SettingsSwitchRow(
                      icon: LucideIcons.bug,
                      title: l.settingsCrashReports,
                      subtitle: l.settingsCrashReportsHint,
                      value: state.crashReports,
                      onChanged: _settings.setCrashReports,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionLabel(l.settingsMore),
              SettingsCard(
                children: [
                  BlocBuilder<SettingsController, SettingsState>(
                    bloc: _settings,
                    buildWhen: (a, b) => a.packageInfo != b.packageInfo,
                    builder: (context, state) => SettingsLinkRow(
                      icon: LucideIcons.info,
                      title: l.settingsAbout,
                      subtitle: switch (state.packageInfo) {
                        final app? => l.settingsVersion(app.version),
                        null => null,
                      },
                      value: null,
                      onTap: _openAbout,
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
