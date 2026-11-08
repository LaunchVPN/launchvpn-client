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

  /// Where the new child starts from its place. Its x runs toward the end of
  /// a line, so it mirrors in a right-to-left language.
  final Offset shift;
  final Duration duration;

  /// How long the old child takes to leave: [duration] when null.
  final Duration? reverseDuration;
  final Curve curve;

  /// Where the children sit over each other.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final shift = switch (Directionality.of(context)) {
      TextDirection.ltr => this.shift,
      TextDirection.rtl => this.shift.scale(-1, 1),
    };
    return AnimatedSwitcher(
      duration: BrandMotion.of(context, duration),
      reverseDuration: BrandMotion.of(context, reverseDuration ?? duration),
      switchInCurve: curve,
      switchOutCurve: curve,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => _Leaving(
        animation: animation,
        child: FadeTransition(
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
      ),
      child: child,
    );
  }
}

/// Opens room for [child] as it fades in, and closes it as [child] fades out,
/// so what sits below moves along instead of jumping. A new [child], told
/// apart by its key, takes the place of the old one the same way.
class BrandReveal extends StatelessWidget {
  const BrandReveal({super.key, required this.child});

  /// Null for nothing.
  final Widget? child;

  /// How long opening and closing take, which whatever moves along matches.
  static const duration = BrandMotion.fast;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: BrandMotion.of(context, duration),
    switchInCurve: BrandMotion.smoothOut,
    switchOutCurve: BrandMotion.smoothOut,
    layoutBuilder: (current, previous) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...previous, ?current],
    ),
    transitionBuilder: (child, animation) => _Leaving(
      animation: animation,
      child: FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: AlignmentDirectional.topStart,
          child: child,
        ),
      ),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}

/// Keeps taps, focus and screen readers off [child] while [animation] takes
/// it away, so only what replaces it answers.
class _Leaving extends StatelessWidget {
  const _Leaving({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final leaving = !animation.status.isForwardOrCompleted;
      return IgnorePointer(
        ignoring: leaving,
        child: ExcludeFocus(
          excluding: leaving,
          child: ExcludeSemantics(excluding: leaving, child: child),
        ),
      );
    },
    child: child,
  );
}
