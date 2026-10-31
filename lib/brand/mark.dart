import 'package:material_ui/material_ui.dart';

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
