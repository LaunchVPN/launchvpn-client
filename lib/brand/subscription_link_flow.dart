import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/servers/subscription/failure.dart';
import 'package:onexray/service/servers/subscription/model.dart';

/// Applies a deep link delivered by the system, without any form.
///
/// Asks before replacing a different subscription, shows progress during the
/// download and reconnect, and reports the outcome in a toast.
Future<void> openSubscriptionLink(
  BuildContext context,
  Uri uri, {
  SubscriptionLinkService? service,
}) async {
  final l = AppLocalizations.of(context)!;
  final link = SubscriptionDeepLink.parse(uri);
  if (link == null) {
    ContextAlert.showToast(context, l.subscriptionLinkInvalid);
    return;
  }
  final subscriptions = service ?? SubscriptionLinkService();
  final bool replaces;
  try {
    replaces = await subscriptions.replacesAnother(link);
  } catch (error) {
    if (!context.mounted) return;
    ContextAlert.showToast(
      context,
      subscriptionFailureMessage(
        l,
        SubscriptionUpdateResult.writeFailed,
        error: error,
      ),
    );
    return;
  }
  if (!context.mounted) return;
  if (replaces) {
    final confirmed = await ContextAlert.showConfirmDialog(
      context,
      title: l.subscriptionLinkReplaceTitle,
      content: l.subscriptionLinkReplaceMessage,
      confirmLabel: l.subscriptionLinkReplaceConfirm,
    );
    if (!confirmed || !context.mounted) return;
  }

  final navigator = Navigator.of(context);
  final progress = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _SubscriptionLinkProgress(message: l.subscriptionLinkAdding),
  );
  unawaited(navigator.push(progress));
  final result = await subscriptions.apply(link);
  // Another dialog may have opened above it, so this cannot pop the top route.
  if (progress.isActive) navigator.removeRoute(progress);
  if (!context.mounted) return;
  ContextAlert.showToast(
    context,
    result.success
        ? l.subscriptionLinkAdded
        : subscriptionFailureMessage(l, result.status, error: result.error),
  );
}

class _SubscriptionLinkProgress extends StatelessWidget {
  const _SubscriptionLinkProgress({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      content: Row(
        children: [
          const ButtonProgressIndicator(size: 20),
          const SizedBox(width: 16),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
