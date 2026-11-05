import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';

/// The mockups' bottom sheet that confirms a destructive step: a title, what
/// happens, the red action and «Отмена».
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final String action;

  /// Above the tab bar. True only when the person takes [action].
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async =>
      await _showSheet<bool>(
        context,
        ConfirmSheet(title: title, body: body, action: action),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => _SheetBody(
    title: title,
    body: body,
    buttons: [
      FilledButton(
        style: BrandTheme.dangerButton,
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(action),
      ),
      const SizedBox(height: 8),
      TextButton(
        style: BrandTheme.quietButton,
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(AppLocalizations.of(context)!.buttonCancel),
      ),
    ],
  );
}

/// The mockups' bottom sheet that explains why something did not happen: a
/// title, the way forward and one button that closes it.
class NoticeSheet extends StatelessWidget {
  const NoticeSheet({
    super.key,
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final String action;

  /// Above the tab bar, until closed.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) => _showSheet<void>(
    context,
    NoticeSheet(title: title, body: body, action: action),
  );

  @override
  Widget build(BuildContext context) => _SheetBody(
    title: title,
    body: body,
    buttons: [
      FilledButton(
        style: BrandTheme.primaryButton,
        onPressed: () => Navigator.of(context).pop(),
        child: Text(action),
      ),
    ],
  );
}

Future<T?> _showSheet<T>(BuildContext context, Widget sheet) =>
    showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BrandRadii.card),
        ),
      ),
      builder: (_) => sheet,
    );

/// A sheet's title and text, centred, above its [buttons].
class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.body,
    required this.buttons,
  });

  final String title;
  final String body;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        BrandSpacing.page,
        0,
        BrandSpacing.page,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: BrandText.screenTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(body, style: BrandText.hint, textAlign: TextAlign.center),
          const SizedBox(height: 28),
          ...buttons,
        ],
      ),
    ),
  );
}
