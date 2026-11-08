import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/pressable.dart';
import 'package:onexray/brand/theme.dart';

enum ConnectToggleState { off, transitioning, on }

/// The state reads from the knob's position: left is off, the middle is a
/// transition, right is on.
class ConnectToggle extends StatelessWidget {
  const ConnectToggle({
    super.key,
    required this.state,
    required this.label,
    required this.onPressed,
  });

  static const _width = 208.0;
  static const _height = 104.0;
  static const _knob = 88.0;

  final ConnectToggleState state;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final duration = BrandMotion.of(context, BrandMotion.fast);
    final off = state == ConnectToggleState.off;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      toggled: state == ConnectToggleState.on,
      label: label,
      child: Pressable(
        onTap: onPressed,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: duration,
            curve: BrandMotion.smoothOut,
            width: _width,
            height: _height,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: switch (state) {
                ConnectToggleState.off => BrandColors.surface,
                ConnectToggleState.transitioning => BrandColors.accentSoft,
                ConnectToggleState.on => BrandColors.accent,
              },
              borderRadius: BorderRadius.circular(_height / 2),
              border: Border.all(
                color: off ? BrandColors.line : Colors.transparent,
              ),
            ),
            child: AnimatedAlign(
              duration: duration,
              curve: BrandMotion.smoothOut,
              alignment: switch (state) {
                ConnectToggleState.off => Alignment.centerLeft,
                ConnectToggleState.transitioning => Alignment.center,
                ConnectToggleState.on => Alignment.centerRight,
              },
              child: AnimatedContainer(
                duration: duration,
                curve: BrandMotion.smoothOut,
                width: _knob,
                height: _knob,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: off
                      ? BrandColors.surfaceRaised
                      : BrandColors.accentInk,
                  border: off ? Border.all(color: BrandColors.line) : null,
                  boxShadow: BrandShadows.knob,
                ),
                child: LaunchMark.knob(
                  color: off ? BrandColors.muted : BrandColors.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
