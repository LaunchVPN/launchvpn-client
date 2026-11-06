import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/launch_reveal.dart';
import 'package:onexray/brand/theme.dart';

/// The app icon from the mockups: the mark on an accent tile. The mark and the
/// corners keep their proportions at any [size].
class LaunchMarkTile extends StatelessWidget {
  const LaunchMarkTile({super.key, this.size = _baseSize});

  /// The tile the mockups draw the mark and corners for.
  static const _baseSize = 64.0;
  static const _baseMark = 36.0;

  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = size / _baseSize;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BrandColors.accentSoft,
        border: Border.all(color: BrandColors.accent),
        borderRadius: BorderRadius.circular(BrandRadii.card * scale),
      ),
      // On «Вход», the launch mark lands here.
      child: LaunchMarkLanding(
        child: LaunchMark.tile(
          color: BrandColors.accent,
          size: _baseMark * scale,
        ),
      ),
    );
  }
}

/// The logo's chevron. [inset] and [stroke] are fractions of [size], because the
/// mockups draw the mark slightly differently in the header and on the knob.
class LaunchMark extends StatelessWidget {
  const LaunchMark.logo({super.key, required this.color})
    : size = 22,
      inset = 0.28125,
      stroke = 0.09375;

  /// Inside [LaunchMarkTile].
  const LaunchMark.tile({super.key, required this.color, this.size = 36})
    : inset = 0.28125,
      stroke = 0.09375;

  /// The launch screens draw it at 64, centered, natively and in the App's
  /// first frames. It keeps the logo's proportions, so it can shrink into it.
  const LaunchMark.splash({super.key, required this.color, this.size = 64})
    : inset = 0.28125,
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
