import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// Taps [child] into [onTap], and shrinks it a little while a finger holds it,
/// so a tap answers at once. A quick tap still plays the whole press. Without
/// [onTap], or when the system asks for less motion, [child] keeps its size.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController(
    vsync: this,
    duration: BrandMotion.quick,
  );
  late final _scale = Tween(begin: 1.0, end: BrandMotion.press).animate(
    CurvedAnimation(
      parent: _press,
      curve: BrandMotion.smoothOut,
      reverseCurve: BrandMotion.smoothOut.flipped,
    ),
  );
  bool _held = false;

  @override
  void didUpdateWidget(Pressable old) {
    super.didUpdateWidget(old);
    if (widget.onTap == null) _hold(false);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _hold(bool held) {
    _held = held && !MediaQuery.disableAnimationsOf(context);
    _follow();
  }

  /// Goes all the way in before coming back, so a tap shorter than the press
  /// still shows it.
  void _follow() {
    if (_press.isAnimating) return;
    if (_press.value == (_held ? 1 : 0)) return;
    (_held ? _press.forward() : _press.reverse()).then((_) {
      if (mounted) _follow();
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onTapDown: widget.onTap == null ? null : (_) => _hold(true),
    onTapUp: widget.onTap == null ? null : (_) => _hold(false),
    onTapCancel: widget.onTap == null ? null : () => _hold(false),
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}
