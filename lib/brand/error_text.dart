import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/swap.dart';
import 'package:onexray/brand/theme.dart';

/// Why the last attempt failed, read out when it appears.
class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Semantics(liveRegion: true, child: Text(message, style: BrandText.error));
}

/// [message] below a field, which opens room for it as it appears and closes
/// it as it goes. Null for none.
class ErrorReveal extends StatelessWidget {
  const ErrorReveal(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) => BrandReveal(
    child: switch (message) {
      null => null,
      final message => Padding(
        key: ValueKey(message),
        padding: const EdgeInsets.only(top: 12),
        child: ErrorText(message),
      ),
    },
  );
}
