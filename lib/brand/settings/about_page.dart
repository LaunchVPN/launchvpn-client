import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/external_link.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/settings/controller.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/top_bar.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';

/// «О приложении»: the version with its build, the license, the project we
/// forked, the privacy policy and support. Every row opens a link outside the
/// App.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.settings, required this.home});

  /// Holds the version.
  final SettingsController settings;

  /// Holds the subscription whose panel may name its own support.
  final HomeController home;

  static final _license = Uri.parse(
    'https://www.gnu.org/licenses/gpl-3.0.html',
  );
  static final _oneXray = Uri.parse('https://github.com/YuanDevTeam/OneXray');

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
              BrandTopBar(title: l.settingsAbout),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    BrandSpacing.page,
                    8,
                    BrandSpacing.page,
                    MediaQuery.paddingOf(context).bottom + 24,
                  ),
                  children: [
                    _Identity(settings: settings),
                    const SizedBox(height: 16),
                    SettingsCard(
                      children: [
                        SettingsLinkRow(
                          icon: LucideIcons.info,
                          title: l.aboutLicense,
                          value: 'GPL-3.0',
                          onTap: () => openExternalLink(_license, 'license'),
                        ),
                        SettingsLinkRow(
                          icon: LucideIcons.link,
                          title: l.aboutBasedOn('OneXray'),
                          subtitle: linkLabel(_oneXray),
                          value: null,
                          onTap: () => openExternalLink(_oneXray, 'OneXray'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SettingsCard(
                      children: [
                        SettingsLinkRow(
                          icon: LucideIcons.shield,
                          title: l.aboutPrivacy,
                          value: null,
                          onTap: () =>
                              openExternalLink(_privacy(context), 'privacy'),
                        ),
                        BlocBuilder<HomeController, HomeState>(
                          bloc: home,
                          buildWhen: (a, b) =>
                              a.subscription?.supportUrl !=
                              b.subscription?.supportUrl,
                          builder: (context, state) => SettingsLinkRow(
                            icon: LucideIcons.messageCircle,
                            title: l.aboutSupport,
                            subtitle: linkLabel(supportUri(state.subscription)),
                            value: null,
                            onTap: () => openSupport(state.subscription),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The policy in the language the App shows.
  static Uri _privacy(BuildContext context) =>
      Uri.parse(Brand.privacyUrl(Localizations.localeOf(context).languageCode));
}

/// The logo, the name, and the version with its build.
class _Identity extends StatelessWidget {
  const _Identity({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const LaunchMarkTile(size: 72),
          const SizedBox(height: 10),
          Text(Brand.name, style: BrandText.topBar),
          const SizedBox(height: 10),
          BlocBuilder<SettingsController, SettingsState>(
            bloc: settings,
            buildWhen: (a, b) => a.packageInfo != b.packageInfo,
            builder: (context, state) => Text(switch (state.packageInfo) {
              final app? => l.aboutVersion(app.version, app.buildNumber),
              null => '',
            }, style: BrandText.caption),
          ),
        ],
      ),
    );
  }
}
