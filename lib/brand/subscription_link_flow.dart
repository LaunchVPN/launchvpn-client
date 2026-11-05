import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/sheet.dart';
import 'package:onexray/brand/toast.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
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
    showBrandToast(context, l.subscriptionLinkInvalid, kind: ToastKind.error);
    return;
  }
  final subscriptions = service ?? SubscriptionLinkService();
  final bool replaces;
  try {
    replaces = await subscriptions.replacesAnother(link);
  } catch (error) {
    if (!context.mounted) return;
    showBrandToast(
      context,
      subscriptionFailureMessage(
        l,
        SubscriptionUpdateResult.writeFailed,
        error: error,
      ),
      kind: ToastKind.error,
    );
    return;
  }
  if (!context.mounted) return;
  if (replaces) {
    final confirmed = await ConfirmSheet.show(
      context,
      title: l.subscriptionLinkReplaceTitle,
      body: l.subscriptionLinkReplaceMessage,
      action: l.subscriptionLinkReplaceConfirm,
    );
    if (!confirmed || !context.mounted) return;
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = ProgressSheet.route(context, l.subscriptionLinkAdding);
  unawaited(navigator.push(progress));
  final result = await subscriptions.apply(link);
  // Another dialog may have opened above it, so this cannot pop the top route.
  if (progress.isActive) navigator.removeRoute(progress);
  if (!context.mounted) return;
  showBrandToast(
    context,
    result.success
        ? l.subscriptionLinkAdded
        : subscriptionFailureMessage(l, result.status, error: result.error),
    kind: result.success ? ToastKind.success : ToastKind.error,
  );
}
