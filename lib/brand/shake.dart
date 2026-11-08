import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// Shakes [child] sideways once whenever [trigger] changes, as a field does
/// at a wrong answer. With less motion it keeps still.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});

  /// A new value shakes once more.
  final Object? trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  /// There, back past the middle, a smaller swing, home: a swing apiece.
  static final _swings = TweenSequence<double>([
    for (final (from, to) in [
      (0.0, BrandMotion.swing),
      (BrandMotion.swing, -BrandMotion.swing),
      (-BrandMotion.swing, BrandMotion.nudge),
      (BrandMotion.nudge, 0.0),
    ])
      TweenSequenceItem(
        tween: Tween(
          begin: from,
          end: to,
        ).chain(CurveTween(curve: BrandMotion.smoothOut)),
        weight: 1,
      ),
  ]);

  late final _shake = AnimationController(
    vsync: this,
    duration: BrandMotion.micro * 4,
  );
  late final _offset = _swings.animate(_shake);

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && !BrandMotion.reduced(context)) {
      unawaited(_shake.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _offset,
    builder: (context, child) =>
        Transform.translate(offset: Offset(_offset.value, 0), child: child),
    child: widget.child,
  );
}
