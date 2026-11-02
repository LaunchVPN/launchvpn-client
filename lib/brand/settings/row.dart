import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// A card of rows split by lines, as the settings mockups draw them.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: BrandColors.surface,
      borderRadius: BorderRadius.circular(BrandRadii.card),
      border: Border.all(color: BrandColors.line),
    ),
    child: Column(
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const Divider(height: 1, color: BrandColors.line),
          child,
        ],
      ],
    ),
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.value,
    this.selected,
    this.toggled,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// What assistive technology reads as the row's current value.
  final String? value;
  final Widget? trailing;

  /// Null where the row is not one of several choices.
  final bool? selected;

  /// Null where the row is not a switch.
  final bool? toggled;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: toggled == null,
    enabled: onTap != null,
    selected: selected,
    toggled: toggled,
    label: subtitle == null ? title : '$title, $subtitle',
    value: value,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: BrandColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(BrandRadii.segment),
                  ),
                  child: Icon(icon, size: 18, color: BrandColors.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: BrandText.cardTitle),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: BrandText.caption),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
