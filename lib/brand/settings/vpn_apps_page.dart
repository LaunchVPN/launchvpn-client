import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/settings/vpn_apps_controller.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/top_bar.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/android/app_icon/controller.dart';
import 'package:onexray/pages/advanced/tunnel/android/app_icon/view.dart';
import 'package:onexray/service/advanced/tunnel/android/app_icon.dart';
import 'package:onexray/service/connect/preset.dart';

/// Picks [preset] for the next connection. «Приложения» with nothing chosen
/// opens the list first, and stays unpicked if the person chooses nothing.
Future<void> choosePreset(
  BuildContext context,
  HomeController home,
  ConnectionPreset preset,
  ConnectionActionRunner run,
) => preset == ConnectionPreset.apps && home.state.vpnApps.isEmpty
    ? editVpnApps(context, home, run, select: true)
    : home.selectPreset(preset, run);

/// Opens «Приложения через VPN» above the tabs and saves the list once the
/// person leaves it, so the tunnel reconnects at most once.
Future<void> editVpnApps(
  BuildContext context,
  HomeController home,
  ConnectionActionRunner run, {
  bool select = false,
}) async {
  final chosen = await Navigator.of(context, rootNavigator: true)
      .push<List<String>>(
        MaterialPageRoute(
          builder: (_) => VpnAppsPage(
            chosen: home.state.vpnApps,
            installedApps: home.installedApps,
          ),
        ),
      );
  if (chosen != null) await home.saveVpnApps(chosen, run, select: select);
}

/// Pops with the chosen package names, or null when the list never arrived.
class VpnAppsPage extends StatefulWidget {
  const VpnAppsPage({
    super.key,
    required this.chosen,
    required this.installedApps,
  });

  final List<String> chosen;
  final InstalledApps installedApps;

  @override
  State<VpnAppsPage> createState() => _VpnAppsPageState();
}

class _VpnAppsPageState extends State<VpnAppsPage> {
  late final _controller = VpnAppsController(
    chosen: widget.chosen,
    load: widget.installedApps,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    unawaited(_controller.close());
    // The icons belong to this screen alone.
    unawaited(AppIconService().clear());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopScope<List<String>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_controller.state.result);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: BrandTheme.statusBar,
        child: BlocProvider(
          create: (_) => TunAppIconController(),
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  BrandTopBar(title: l.settingsVpnApps),
                  Expanded(
                    child: BlocBuilder<VpnAppsController, VpnAppsState>(
                      bloc: _controller,
                      builder: (context, state) => _body(l, state),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l, VpnAppsState state) {
    if (state.failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.vpnAppsLoadFailed, style: BrandText.hint),
            TextButton(
              onPressed: _controller.load,
              child: Text(l.prototypeRetry),
            ),
          ],
        ),
      );
    }
    if (state.apps == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final first = state.first;
    final others = state.others;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        BrandSpacing.page,
        0,
        BrandSpacing.page,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      children: [
        _SearchField(hint: l.vpnAppsSearch, onChanged: _controller.search),
        const SizedBox(height: 24),
        if (first.isEmpty && others.isEmpty)
          Text(l.vpnAppsNone, style: BrandText.hint),
        if (first.isNotEmpty) ...[
          SettingsSectionLabel(l.vpnAppsChosen(state.chosen.length)),
          _group(first, state.chosen),
          const SizedBox(height: 24),
        ],
        if (others.isNotEmpty) ...[
          SettingsSectionLabel(l.vpnAppsOthers),
          _group(others, state.chosen),
        ],
      ],
    );
  }

  Widget _group(List<AndroidAppInfo> apps, Set<String> chosen) => SettingsCard(
    children: [
      for (final app in apps)
        SettingsSwitchRow(
          key: ValueKey(app.packageName),
          leading: _AppIcon(app.packageName),
          title: app.name,
          value: chosen.contains(app.packageName),
          onChanged: (_) => _controller.toggle(app.packageName),
        ),
    ],
  );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon(this.packageName);

  final String packageName;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 36,
    child: IconTheme(
      data: const IconThemeData(size: 18, color: BrandColors.muted),
      child: AppIconView(packageName: packageName),
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(BrandRadii.md),
      borderSide: const BorderSide(color: BrandColors.line),
    );
    return TextField(
      onChanged: onChanged,
      style: BrandText.body,
      cursorColor: BrandColors.accent,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: BrandText.hint,
        filled: true,
        fillColor: BrandColors.surface,
        prefixIcon: const Icon(
          LucideIcons.search,
          size: 20,
          color: BrandColors.muted,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: BrandColors.accent),
        ),
      ),
    );
  }
}
