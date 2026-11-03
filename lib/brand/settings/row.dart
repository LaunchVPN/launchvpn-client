import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/icon_tile.dart';
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
/// the value is unknown, which disables the row.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value;
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      toggled: current ?? false,
      onTap: current == null ? null : () => onChanged(!current),
      trailing: IgnorePointer(
        child: ShadSwitch(
          value: current ?? false,
          width: 51,
          height: 31,
          margin: 2,
        ),
      ),
    );
  }
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
                IconTile(
                  icon: icon,
                  color: BrandColors.ink,
                  fill: BrandColors.surfaceRaised,
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
