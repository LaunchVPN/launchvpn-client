import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/brand/sheet.dart';
import 'package:onexray/brand/toast.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/account/failure.dart';

/// Tells how «Привязать Telegram» ended, on «Аккаунт» or Home; turning
/// Telegram down says nothing.
Future<void> tellTelegramLink(
  BuildContext context,
  TelegramLinkOutcome outcome,
) async {
  final l = AppLocalizations.of(context)!;
  switch (outcome) {
    case TelegramLinked(:final addedDays):
      showBrandToast(
        context,
        addedDays > 0
            ? l.accountTelegramLinkedDays(addedDays)
            : l.accountTelegramLinked,
        kind: ToastKind.success,
      );
    case TelegramLinkFailed(error: AccountError.cancelled):
      break;
    case TelegramLinkFailed(error: AccountError.telegramTaken):
      await NoticeSheet.show(
        context,
        title: l.accountTelegramTakenTitle,
        body: l.accountTelegramTakenBody,
        action: l.accountTelegramTakenOk,
      );
    case TelegramLinkFailed():
      showBrandToast(
        context,
        l.accountLinkTelegramFailed,
        kind: ToastKind.error,
      );
  }
}
