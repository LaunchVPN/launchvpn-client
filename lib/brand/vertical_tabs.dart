import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/pressable.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/pigeon/messages.g.dart';

/// The tabs as iOS lays its own down the vertical bar on iPhone Duo: icons in
/// a capsule low in the column, under the middle of the status items, the
/// chosen one on a highlight that slides between them. The sizes and places
/// are the system tab bar's, so the App's sits like the others'. Fills the
/// column down to where [bar] says the tabs end.
class VerticalTabs extends StatelessWidget {
  const VerticalTabs({
    super.key,
    required this.bar,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final VerticalBar bar;
  final List<(IconData, String)> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  static const _width = 48.0;

  /// From one icon to the next.
  static const _pitch = 50.0;
  static const _inset = 6.0;

  /// Between the highlight and the capsule's edge, the same on every side the
  /// highlight reaches, so both curves share one center.
  static const _gap = 3.0;

  /// Between the capsule and the pages beside it.
  static const _pagesGap = 12.0;

  /// Above the screen's bottom edge. A region below the capsule, such as the
  /// camera's, already keeps its own margin.
  static const _lift = 24.0;

  @override
  Widget build(BuildContext context) {
    final right = bar.side == VerticalBarSide.right;
    return Padding(
      padding: EdgeInsets.only(
        left: right ? _pagesGap : 0,
        right: right ? 0 : _pagesGap,
        bottom: bar.bottom < MediaQuery.sizeOf(context).height ? 0 : _lift,
      ),
      child: Align(
        alignment: right ? Alignment.bottomLeft : Alignment.bottomRight,
        child: _capsule(context),
      ),
    );
  }

  Widget _capsule(BuildContext context) => DecoratedBox(
    decoration: const ShapeDecoration(
      color: BrandColors.surface,
      shape: StadiumBorder(side: BorderSide(color: BrandColors.line)),
    ),
    child: SizedBox(
      width: _width,
      height: tabs.length * _pitch + 2 * _inset,
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: BrandMotion.of(context, BrandMotion.fast),
            curve: BrandMotion.smoothOut,
            left: _gap,
            top: _gap + selected * _pitch,
            width: _width - 2 * _gap,
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
                        width: _width,
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
