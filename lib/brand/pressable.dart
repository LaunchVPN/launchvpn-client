import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// Taps [child] into [onTap], and shrinks it a little while a finger holds it,
/// so a tap answers at once. A quick tap still plays the whole press. Without
/// [onTap], or when the system asks for less motion, [child] keeps its size.
/// A [Pressable] inside another answers alone: the outer one keeps its size
/// while the inner one holds the finger.
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

  /// While a [Pressable] inside holds the finger.
  bool _innerHeld = false;

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
    _held = held && !_innerHeld && !BrandMotion.reduced(context);
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

  /// Tells the [Pressable]s around this one whether it holds the finger. The
  /// pointer reaches this before their tap-down, which comes only once the
  /// press outlasts a tap.
  void _holdOuter(bool held) {
    for (
      var outer = context.findAncestorStateOfType<_PressableState>();
      outer != null;
      outer = outer.context.findAncestorStateOfType<_PressableState>()
    ) {
      outer._innerHeld = held;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Listener(
      onPointerDown: enabled ? (_) => _holdOuter(true) : null,
      onPointerUp: enabled ? (_) => _holdOuter(false) : null,
      onPointerCancel: enabled ? (_) => _holdOuter(false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _hold(true) : null,
        onTapUp: enabled ? (_) => _hold(false) : null,
        onTapCancel: enabled ? () => _hold(false) : null,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}
