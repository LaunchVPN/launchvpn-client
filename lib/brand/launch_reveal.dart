import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/theme.dart';

/// The launch screen inside the App: the mark in the middle, where the native
/// launch screens draw it, until [child] is ready. Then [child] fades in while
/// the mark flies into the [LaunchMarkLanding] that [child] shows, or fades
/// where it is when there is none. Later changes of [child] show at once.
class LaunchReveal extends StatefulWidget {
  const LaunchReveal({super.key, required this.child});

  /// Null while the App is still loading.
  final Widget? child;

  /// A spinner joins the mark only when loading takes this long.
  static const spinnerDelay = Duration(seconds: 1);
  static const duration = Duration(milliseconds: 300);

  @override
  State<LaunchReveal> createState() => _LaunchRevealState();
}

class _LaunchRevealState extends State<LaunchReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: LaunchReveal.duration,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  final _flight = _Flight();
  final _stack = GlobalKey();
  Timer? _spinnerTimer;
  bool _spinner = false;
  bool _revealing = false;
  bool _revealed = false;

  /// Counts reveals, so a stopped one never finishes a later one.
  int _run = 0;

  /// Where the mark lands, in the stack's coordinates. Null when it fades.
  Rect? _landing;

  @override
  void initState() {
    super.initState();
    _waitForChild();
    if (widget.child != null) _reveal();
  }

  @override
  void didUpdateWidget(LaunchReveal old) {
    super.didUpdateWidget(old);
    if (widget.child == null) {
      // A retry after a start-up error: the mark comes back until it is ready.
      if (_revealing || _revealed) _restart();
    } else if (_controller.isAnimating) {
      // The page may have changed mid-flight, as «Вход» giving way to the tabs.
      final run = _run;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && run == _run && !_revealed) {
          setState(() => _landing = _measureLanding());
        }
      });
    } else {
      _reveal();
    }
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
    _progress.dispose();
    _controller.dispose();
    _flight.dispose();
    super.dispose();
  }

  void _waitForChild() {
    _spinner = false;
    _spinnerTimer?.cancel();
    _spinnerTimer = Timer(LaunchReveal.spinnerDelay, () {
      if (mounted) setState(() => _spinner = true);
    });
  }

  void _restart() {
    _run++;
    _controller.value = 0;
    _revealing = false;
    _revealed = false;
    _landing = null;
    _flight.takeOff();
    _waitForChild();
  }

  /// Waits one frame, so [LaunchReveal.child] has laid out its landing.
  void _reveal() {
    if (_revealing || _revealed) return;
    _revealing = true;
    _spinnerTimer?.cancel();
    final run = ++_run;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || run != _run) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
        return _finish();
      }
      setState(() => _landing = _measureLanding());
      _controller.forward().whenCompleteOrCancel(() {
        if (run == _run) _finish();
      });
    });
  }

  Rect? _measureLanding() {
    final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
    final target = _flight.target?.findRenderObject() as RenderBox?;
    if (stack == null || target == null || !target.attached) return null;
    return MatrixUtils.transformRect(
      target.getTransformTo(stack),
      Offset.zero & target.size,
    );
  }

  void _finish() {
    if (!mounted) return;
    setState(() => _revealed = true);
    _flight.land();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final content = child == null
        ? null
        : _FlightScope(flight: _flight, child: child);
    // One tree throughout, so [child] keeps its state once the mark is gone.
    return LayoutBuilder(
      builder: (context, constraints) {
        final center = Rect.fromCenter(
          center: constraints.biggest.center(Offset.zero),
          width: _markSize,
          height: _markSize,
        );
        return Stack(
          key: _stack,
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: BrandColors.bg),
            if (content != null)
              FadeTransition(opacity: _progress, child: content),
            if (!_revealed) ...[
              AnimatedBuilder(
                animation: _progress,
                builder: (context, _) {
                  final t = _progress.value;
                  final landing = _landing;
                  final rect = landing == null
                      ? center
                      : Rect.lerp(center, landing, t)!;
                  return Positioned.fromRect(
                    rect: rect,
                    child: Opacity(
                      opacity: landing == null ? 1 - t : 1,
                      child: LaunchMark.splash(
                        color: BrandColors.accent,
                        size: rect.width,
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                top: center.bottom + 24,
                child: AnimatedOpacity(
                  opacity: _spinner && !_revealing ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static const _markSize = 64.0;
}

/// Where the launch mark lands. [child] is the mark itself, drawn with the
/// splash's proportions, and stays hidden until the mark arrives. Outside a
/// launch, or once it is over, [child] shows as it is.
class LaunchMarkLanding extends StatefulWidget {
  const LaunchMarkLanding({super.key, required this.child});

  final Widget child;

  @override
  State<LaunchMarkLanding> createState() => _LaunchMarkLandingState();
}

class _LaunchMarkLandingState extends State<LaunchMarkLanding> {
  _Flight? _flight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _flight?.withdraw(context);
    _flight = _FlightScope.maybeOf(context)?..offer(context);
  }

  @override
  void dispose() {
    _flight?.withdraw(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flight = _flight;
    if (flight == null) return widget.child;
    return ListenableBuilder(
      listenable: flight,
      builder: (context, child) =>
          Opacity(opacity: flight.landed ? 1 : 0, child: child),
      child: widget.child,
    );
  }
}

/// The first landing to offer itself takes the mark.
class _Flight extends ChangeNotifier {
  BuildContext? target;
  bool landed = false;

  void offer(BuildContext context) => target ??= context;

  void withdraw(BuildContext context) {
    if (target == context) target = null;
  }

  void land() {
    landed = true;
    notifyListeners();
  }

  /// Before another reveal. The landings of the page that left are gone, and
  /// the next page's read [landed] when they build.
  void takeOff() {
    landed = false;
    target = null;
  }
}

class _FlightScope extends InheritedWidget {
  const _FlightScope({required this.flight, required super.child});

  final _Flight flight;

  static _Flight? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FlightScope>()?.flight;

  @override
  bool updateShouldNotify(_FlightScope old) => flight != old.flight;
}
