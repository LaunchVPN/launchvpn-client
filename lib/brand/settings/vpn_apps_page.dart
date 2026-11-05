import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/settings/vpn_apps_controller.dart';
import 'package:onexray/brand/text_field.dart';
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
    // Rows build as they scroll in, so only visible apps ask for icons.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            BrandSpacing.page,
            0,
            BrandSpacing.page,
            24,
          ),
          sliver: SliverToBoxAdapter(
            child: BrandTextField(
              icon: LucideIcons.search,
              hint: l.vpnAppsSearch,
              onChanged: _controller.search,
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
        if (first.isEmpty && others.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: BrandSpacing.page),
            sliver: SliverToBoxAdapter(
              child: Text(l.vpnAppsNone, style: BrandText.hint),
            ),
          ),
        if (first.isNotEmpty)
          ..._group(
            l.vpnAppsChosen(state.chosen.length),
            first,
            state.chosen,
            last: others.isEmpty,
          ),
        if (others.isNotEmpty)
          ..._group(l.vpnAppsOthers, others, state.chosen, last: true),
      ],
    );
  }

  /// A labelled card of rows, as [SettingsCard] draws it.
  List<Widget> _group(
    String label,
    List<AndroidAppInfo> apps,
    Set<String> chosen, {
    required bool last,
  }) => [
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: BrandSpacing.page),
      sliver: SliverToBoxAdapter(child: SettingsSectionLabel(label)),
    ),
    SliverPadding(
      padding: EdgeInsets.fromLTRB(
        BrandSpacing.page,
        0,
        BrandSpacing.page,
        last ? MediaQuery.paddingOf(context).bottom + 20 : 24,
      ),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color: BrandColors.surface,
          borderRadius: BorderRadius.circular(BrandRadii.card),
          border: Border.all(color: BrandColors.line),
        ),
        sliver: SliverList.separated(
          itemCount: apps.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: BrandColors.line),
          itemBuilder: (_, index) {
            final app = apps[index];
            return SettingsSwitchRow(
              key: ValueKey(app.packageName),
              leading: _AppIcon(app.packageName),
              title: app.name,
              value: chosen.contains(app.packageName),
              onChanged: (_) => _controller.toggle(app.packageName),
            );
          },
        ),
      ),
    ),
  ];
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
