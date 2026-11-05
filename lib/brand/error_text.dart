import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// Why the last attempt failed, read out when it appears.
class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Semantics(liveRegion: true, child: Text(message, style: BrandText.error));
}
