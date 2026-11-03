import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// The mockups' 36 px rounded square that leads a row or a card.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    required this.fill,
  });

  final IconData icon;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(BrandRadii.segment),
    ),
    child: Icon(icon, size: 18, color: color),
  );
}
