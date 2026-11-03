import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// The mockups' centered state: an icon in a tinted circle, a title and a
/// short explanation below it.
class StateHero extends StatelessWidget {
  /// For a step the person takes, such as allowing the VPN.
  const StateHero.accent({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  }) : _color = BrandColors.accent,
       _fill = BrandColors.accentBadge,
       _line = BrandColors.accentBadgeLine;

  /// For something that went wrong.
  const StateHero.danger({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  }) : _color = BrandColors.danger,
       _fill = BrandColors.dangerBadge,
       _line = BrandColors.dangerBadgeLine;

  final IconData icon;
  final String title;
  final String body;
  final Color _color;
  final Color _fill;
  final Color _line;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _fill,
          border: Border.all(color: _line),
        ),
        child: Icon(icon, size: 36, color: _color),
      ),
      const SizedBox(height: 16),
      Text(title, style: BrandText.screenTitle, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      Padding(
        // The mockups narrow the text to 300 of 342. Padding rather than a
        // width limit: a scrolling page measures the height through it.
        padding: const EdgeInsets.symmetric(horizontal: 21),
        child: Text(body, style: BrandText.hint, textAlign: TextAlign.center),
      ),
    ],
  );
}
