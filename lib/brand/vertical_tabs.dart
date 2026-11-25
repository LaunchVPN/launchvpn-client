import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/pressable.dart';
import 'package:onexray/brand/theme.dart';

/// The tabs as iOS lays its own down the vertical bar on iPhone Duo: icons in
/// a capsule, the chosen one on a highlight that slides between them.
/// The sizes are the system tab bar's, so the App's sits like the others'.
class VerticalTabs extends StatelessWidget {
  const VerticalTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<(IconData, String)> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  static const width = 48.0;
  static const _pitch = 50.0;
  static const _inset = 6.0;

  /// Between the highlight and the capsule's edge, the same on every side the
  /// highlight reaches, so both curves share one center.
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const ShapeDecoration(
      color: BrandColors.surface,
      shape: StadiumBorder(side: BorderSide(color: BrandColors.line)),
    ),
    child: SizedBox(
      width: width,
      height: tabs.length * _pitch + 2 * _inset,
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: BrandMotion.of(context, BrandMotion.fast),
            curve: BrandMotion.smoothOut,
            left: _gap,
            top: _gap + selected * _pitch,
            width: width - 2 * _gap,
            height: _pitch + 2 * (_inset - _gap),
            child: const DecoratedBox(
              decoration: ShapeDecoration(
                color: BrandColors.surfaceRaised,
                shape: StadiumBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: _inset),
            child: Column(
              children: [
                for (final (index, (icon, label)) in tabs.indexed)
                  Semantics(
                    button: true,
                    selected: index == selected,
                    label: label,
                    child: Pressable(
                      onTap: () => onSelect(index),
                      child: SizedBox(
                        width: width,
                        height: _pitch,
                        child: Icon(
                          icon,
                          size: 24,
                          color: index == selected
                              ? BrandColors.accent
                              : BrandColors.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
