import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/app_update/service.dart';

/// The mockup's «Доступна версия» card, which an APK build shows on Home
/// while GitHub has a newer release.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.update, required this.onUpdate});

  final AppUpdateInfo update;
  final VoidCallback onUpdate;

  /// The button's 48 touch area fills the mockup's 14 above and below the text
  /// down to 11, and the 1 px border adds the rest.
  static const _padding = EdgeInsetsDirectional.fromSTEB(14, 11, 10, 11);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(BrandRadii.md),
        border: Border.all(color: BrandColors.line),
      ),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: BrandColors.accentSoft,
              borderRadius: BorderRadius.circular(BrandRadii.segment),
            ),
            child: const Icon(
              LucideIcons.download,
              size: 18,
              color: BrandColors.accent,
            ),
          ),
          // A large font moves the button below the text.
          Expanded(
            child: OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              spacing: 12,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      l.homeUpdateAvailable(update.latestVersion),
                      style: BrandText.cardTitle,
                    ),
                    Text(
                      l.homeUpdateCurrent(update.currentVersion),
                      style: BrandText.caption,
                    ),
                  ],
                ),
                FilledButton(
                  style: BrandTheme.smallButton,
                  onPressed: onUpdate,
                  child: Text(l.homeUpdateAction),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
