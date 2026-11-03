import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';

/// Explains the system VPN prompt before it appears, as the mockup's
/// «Состояние — разрешение VPN» frame has it.
class VpnPermissionPage extends StatelessWidget {
  const VpnPermissionPage({super.key});

  /// Opens over the tabs and answers whether the person chose «Продолжить».
  /// Leaving any other way, the back gesture included, means not now.
  static Future<bool> show(BuildContext context) async =>
      await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(builder: (_) => const VpnPermissionPage()),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BrandTheme.statusBar,
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BrandSpacing.page,
                    8,
                    BrandSpacing.page,
                    24,
                  ),
                  child: Column(
                    children: [
                      Expanded(child: Center(child: _Hero(l))),
                      const SizedBox(height: 12),
                      _Points([l.vpnPermissionNoLogs, l.vpnPermissionOneTap]),
                      const SizedBox(height: 32),
                      FilledButton(
                        style: BrandTheme.primaryButton,
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(l.prototypeContinue),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        style: BrandTheme.quietButton,
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(l.vpnPermissionNotNow),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(this.l);

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: BrandColors.accentBadge,
          border: Border.all(color: BrandColors.accentBadgeLine),
        ),
        child: const Icon(
          LucideIcons.shieldCheck,
          size: 36,
          color: BrandColors.accent,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        l.vpnPermissionTitle,
        style: BrandText.screenTitle,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      ConstrainedBox(
        // The mockup breaks the text into three short lines.
        constraints: const BoxConstraints(maxWidth: 300),
        child: Text(
          l.vpnPermissionBody,
          style: BrandText.hint,
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}

class _Points extends StatelessWidget {
  const _Points(this.points);

  final List<String> points;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: BrandColors.surface,
      borderRadius: BorderRadius.circular(BrandRadii.card),
      border: Border.all(color: BrandColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        for (final point in points)
          Row(
            spacing: 10,
            children: [
              const Icon(
                LucideIcons.check,
                size: 18,
                color: BrandColors.accent,
              ),
              Expanded(child: Text(point, style: BrandText.body)),
            ],
          ),
      ],
    ),
  );
}
