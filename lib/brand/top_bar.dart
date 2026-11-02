import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// The back button and title of a screen opened above the tabs.
class BrandTopBar extends StatelessWidget {
  const BrandTopBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      BrandSpacing.page,
      8,
      BrandSpacing.page,
      16,
    ),
    child: Row(
      children: [
        Semantics(
          button: true,
          label: MaterialLocalizations.of(context).backButtonTooltip,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BrandColors.surface,
                borderRadius: BorderRadius.circular(BrandRadii.iconButton),
              ),
              child: const Icon(
                LucideIcons.chevronLeft,
                size: 20,
                color: BrandColors.ink,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: BrandText.topBar)),
      ],
    ),
  );
}
