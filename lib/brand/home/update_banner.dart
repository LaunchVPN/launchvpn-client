import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/icon_tile.dart';
import 'package:onexray/brand/pressable.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/app_update/service.dart';

/// The «Доступна версия» card, which an APK build shows on Home while GitHub
/// has a newer release. The whole card opens it.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.update, required this.onUpdate});

  final AppUpdateInfo update;
  final VoidCallback onUpdate;

  /// The space around the download tile on its three sides, counted from the
  /// outer edge.
  static const _inset = 12.0;

  /// Text has no box of its own, so it needs more room to look as far in.
  static const _textInset = 16.0;
  static const _tile = 36.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Semantics(
      onTapHint: l.homeUpdateAction,
      child: Pressable(
        onTap: onUpdate,
        child: Material(
          color: BrandColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            // Concentric with the tile's corners.
            borderRadius: BorderRadius.circular(BrandRadii.segment + _inset),
            side: const BorderSide(color: BrandColors.line),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _tile + 2 * _inset),
            child: Padding(
              // Enough above and below for the text the system font grows.
              padding: const EdgeInsetsDirectional.fromSTEB(
                _textInset,
                8,
                _inset,
                8,
              ),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
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
                  ),
                  const IconTile(
                    icon: LucideIcons.download,
                    color: BrandColors.accent,
                    fill: BrandColors.accentSoft,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
