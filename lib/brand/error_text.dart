import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/swap.dart';
import 'package:onexray/brand/theme.dart';

/// Why the last attempt failed, below a field and read out when it appears.
/// It opens room for itself as it appears and closes it as it goes. Null for
/// none.
class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) => BrandReveal(
    child: switch (message) {
      null => null,
      final message => Padding(
        key: ValueKey(message),
        padding: const EdgeInsets.only(top: 12),
        child: Semantics(
          liveRegion: true,
          child: Text(message, style: BrandText.error),
        ),
      ),
    },
  );
}
