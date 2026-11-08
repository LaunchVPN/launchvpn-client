import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/icon_tile.dart';
import 'package:onexray/brand/pressable.dart';
import 'package:onexray/brand/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch;

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

/// A row that is one switch: a tap anywhere on it flips [value]. Null while
/// the value is unknown, which disables the row, as a null [onChanged] does.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.leading,
    this.subtitle,
  });

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool? value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value;
    final change = onChanged;
    return SettingsRow(
      icon: icon,
      leading: leading,
      title: title,
      subtitle: subtitle,
      toggled: current ?? false,
      onTap: current == null || change == null ? null : () => change(!current),
      trailing: IgnorePointer(
        child: ShadSwitch(
          value: current ?? false,
          enabled: change != null,
          width: 51,
          height: 31,
          margin: 2,
        ),
      ),
    );
  }
}

/// A row that opens another screen or a link, with the current [value]
/// before the chevron.
class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Null while unknown.
  final String? value;

  /// Null disables the row.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SettingsRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    value: value,
    onTap: onTap,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value case final value?) ...[
          Text(value, style: BrandText.caption),
          const SizedBox(width: 12),
        ],
        const Icon(
          LucideIcons.chevronRight,
          size: 18,
          color: BrandColors.muted,
        ),
      ],
    ),
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    required this.onTap,
    this.icon,
    this.leading,
    this.subtitle,
    this.trailing,
    this.value,
    this.selected,
    this.toggled,
    this.color = BrandColors.ink,
  });

  /// Left out where the mockup draws a plain list of choices.
  final IconData? icon;

  /// Takes the place of [icon] where the picture is not a glyph.
  final Widget? leading;
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

  /// Of the icon and the title; red for a row that ends something.
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: toggled == null,
    enabled: onTap != null,
    selected: selected,
    toggled: toggled,
    label: subtitle == null ? title : '$title, $subtitle',
    value: value,
    child: Pressable(
      onTap: onTap,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (icon case final icon?)
                  IconTile(
                    icon: icon,
                    color: color,
                    fill: BrandColors.surfaceRaised,
                  )
                else
                  ?leading,
                if (icon != null || leading != null) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: BrandText.cardTitle.copyWith(color: color),
                      ),
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
