import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';

/// The tab's title only. Its rows arrive with their features.
class BrandSettingsPage extends StatelessWidget {
  const BrandSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: BrandTheme.statusBar,
    child: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            BrandSpacing.page,
            16,
            BrandSpacing.page,
            0,
          ),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: Text(
              AppLocalizations.of(context)!.prototypeSettings,
              style: BrandText.screenTitle,
            ),
          ),
        ),
      ),
    ),
  );
}
