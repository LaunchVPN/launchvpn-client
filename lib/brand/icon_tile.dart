import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// The mockups' rounded square that leads a row, a card or a toast: 36 px,
/// or 32 in a toast.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    required this.fill,
    this.size = 36,
    this.iconSize = 18,
  });

  final IconData icon;
  final Color color;
  final Color fill;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(BrandRadii.segment),
    ),
    child: Icon(icon, size: iconSize, color: color),
  );
}
