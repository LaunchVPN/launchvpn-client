import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// Swaps [child] for the next one, told apart by its key: the old one fades
/// out toward the opposite of [shift] while the new one fades in from [shift].
/// Both show at once, over each other.
class BrandSwap extends StatelessWidget {
  const BrandSwap({
    super.key,
    required this.child,
    this.shift = Offset.zero,
    this.duration = BrandMotion.quick,
    this.reverseDuration,
    this.curve = BrandMotion.inOut,
    this.alignment = Alignment.center,
  });

  /// Text changing in place: the old line rises out, the new one comes from
  /// below.
  const BrandSwap.text({super.key, required this.child})
    : shift = const Offset(0, BrandMotion.nudge),
      duration = BrandMotion.quick,
      reverseDuration = null,
      curve = BrandMotion.inOut,
      alignment = Alignment.center;

  /// A screen giving way to another, which rises a little as it arrives.
  const BrandSwap.screen({super.key, required this.child})
    : shift = const Offset(0, BrandMotion.step),
      duration = BrandMotion.slow,
      reverseDuration = BrandMotion.medium,
      curve = BrandMotion.smoothOut,
      alignment = Alignment.topCenter;

  final Widget child;

  /// Where the new child starts from its place.
  final Offset shift;
  final Duration duration;

  /// How long the old child takes to leave: [duration] when null.
  final Duration? reverseDuration;
  final Curve curve;

  /// Where the children sit over each other.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: BrandMotion.of(context, duration),
    reverseDuration: BrandMotion.of(context, reverseDuration ?? duration),
    switchInCurve: curve,
    switchOutCurve: curve,
    layoutBuilder: (current, previous) =>
        Stack(alignment: alignment, children: [...previous, ?current]),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Transform.translate(
          // A child on its way out moves on past its place, not back.
          offset:
              shift *
              (1 - animation.value) *
              (animation.status.isForwardOrCompleted ? 1 : -1),
          child: child,
        ),
        child: child,
      ),
    ),
    child: child,
  );
}
