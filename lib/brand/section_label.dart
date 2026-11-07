import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// The name of a group of cards, as in «Настройки» and «Локации».
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 8),
    child: Text(text, style: BrandText.sectionLabel),
  );
}
