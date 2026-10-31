import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

enum ConnectToggleState { off, transitioning, on }

/// The logo's chevron. [inset] and [stroke] are fractions of [size], because the
/// mockups draw the mark slightly differently in the header and on the knob.
class LaunchMark extends StatelessWidget {
  const LaunchMark.logo({super.key, required this.color})
    : size = 22,
      inset = 0.28125,
      stroke = 0.09375;

  const LaunchMark.knob({super.key, required this.color})
    : size = 40,
      inset = 0.25,
      stroke = 0.1125;

  final Color color;
  final double size;
  final double inset;
  final double stroke;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _MarkPainter(color, inset, stroke),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color, this.inset, this.stroke);

  final Color color;
  final double inset;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final path = Path()
      ..moveTo(side * inset, side * (1 - inset * 1.15))
      ..lineTo(side / 2, side * inset)
      ..lineTo(side * (1 - inset), side * (1 - inset * 1.15));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      color != old.color || inset != old.inset || stroke != old.stroke;
}

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
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final off = state == ConnectToggleState.off;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      toggled: state == ConnectToggleState.on,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
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
              curve: Curves.easeOutCubic,
              alignment: switch (state) {
                ConnectToggleState.off => Alignment.centerLeft,
                ConnectToggleState.transitioning => Alignment.center,
                ConnectToggleState.on => Alignment.centerRight,
              },
              child: AnimatedContainer(
                duration: duration,
                width: _knob,
                height: _knob,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: off
                      ? BrandColors.surfaceRaised
                      : BrandColors.accentInk,
                  border: off ? Border.all(color: BrandColors.line) : null,
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.3),
                      offset: Offset(0, 4),
                      blurRadius: 12,
                    ),
                  ],
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
