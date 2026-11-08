import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/pressable.dart';
import 'package:onexray/brand/theme.dart';

enum ConnectToggleState { off, transitioning, on }

/// The state reads from the knob's position: left is off, the middle is a
/// transition, right is on. The track pulses while the connection changes,
/// so a wait reads as work, and the knob lands on with a little bounce.
class ConnectToggle extends StatefulWidget {
  const ConnectToggle({
    super.key,
    required this.state,
    required this.label,
    required this.onPressed,
  });

  static const _width = 208.0;
  static const _height = 104.0;
  static const _knob = 88.0;

  /// Half a breath of the pulse: from the track's color to its lit one.
  static const _pulse = Duration(seconds: 1);

  final ConnectToggleState state;
  final String label;
  final VoidCallback? onPressed;

  @override
  State<ConnectToggle> createState() => _ConnectToggleState();
}

class _ConnectToggleState extends State<ConnectToggle>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: ConnectToggle._pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(ConnectToggle old) {
    super.didUpdateWidget(old);
    _follow();
  }

  /// Breathes while the connection changes, and settles back once it has.
  void _follow() {
    final pulses =
        widget.state == ConnectToggleState.transitioning &&
        !BrandMotion.reduced(context);
    if (pulses) {
      if (!_pulse.isAnimating) unawaited(_pulse.repeat(reverse: true));
    } else if (_pulse.value > 0) {
      unawaited(
        _pulse.animateBack(
          0,
          duration: BrandMotion.of(context, BrandMotion.fast),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final duration = BrandMotion.of(context, BrandMotion.fast);
    final off = state == ConnectToggleState.off;
    final on = state == ConnectToggleState.on;
    final shape = BorderRadius.circular(ConnectToggle._height / 2);
    return Semantics(
      container: true,
      button: true,
      enabled: widget.onPressed != null,
      toggled: on,
      label: widget.label,
      child: Pressable(
        onTap: widget.onPressed,
        child: ExcludeSemantics(
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: switch (state) {
                ConnectToggleState.off => BrandColors.surface,
                ConnectToggleState.transitioning => BrandColors.accentSoft,
                ConnectToggleState.on => BrandColors.accent,
              },
            ),
            duration: duration,
            curve: BrandMotion.smoothOut,
            builder: (context, fill, track) => AnimatedBuilder(
              animation: _pulse,
              builder: (context, track) => DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.lerp(
                    fill,
                    BrandColors.accentSoftLit,
                    BrandMotion.inOut.transform(_pulse.value),
                  ),
                  borderRadius: shape,
                ),
                child: track,
              ),
              child: track,
            ),
            child: AnimatedContainer(
              duration: duration,
              curve: BrandMotion.smoothOut,
              width: ConnectToggle._width,
              height: ConnectToggle._height,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: shape,
                border: Border.all(
                  color: off ? BrandColors.line : Colors.transparent,
                ),
              ),
              child: AnimatedAlign(
                // Arriving on overshoots a little and settles.
                duration: on
                    ? BrandMotion.of(context, BrandMotion.medium)
                    : duration,
                curve: on ? BrandMotion.bounce : BrandMotion.smoothOut,
                alignment: switch (state) {
                  ConnectToggleState.off => Alignment.centerLeft,
                  ConnectToggleState.transitioning => Alignment.center,
                  ConnectToggleState.on => Alignment.centerRight,
                },
                child: AnimatedContainer(
                  duration: duration,
                  curve: BrandMotion.smoothOut,
                  width: ConnectToggle._knob,
                  height: ConnectToggle._knob,
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
      ),
    );
  }
}
