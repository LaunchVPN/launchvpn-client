import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// How long a toast stays when it names something to take in, such as the
/// device a removal freed or the days Telegram added.
const _readingTime = Duration(seconds: 3);

/// Shows [message] the way `ContextAlert.showToast` does, for [duration]
/// instead of its two seconds.
void showReadingToast(
  BuildContext context,
  String message, {
  Duration duration = _readingTime,
}) {
  final size = MediaQuery.sizeOf(context);
  final compact = size.width < 600;
  final availableWidth = math.max(0.0, size.width - 32);
  final maxWidth = compact ? availableWidth : math.min(420.0, availableWidth);
  final minWidth = compact ? maxWidth : math.min(320.0, maxWidth);
  final colors = ShadTheme.of(context).colorScheme;
  ShadToaster.of(context).show(
    ShadToast(
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 18, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      alignment: compact ? Alignment.bottomCenter : Alignment.bottomRight,
      backgroundColor: colors.popover,
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 36, 14),
      crossAxisAlignment: CrossAxisAlignment.start,
      showCloseIconOnlyWhenHovered: false,
      duration: duration,
    ),
  );
}
