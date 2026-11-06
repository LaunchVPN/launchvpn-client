import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/text_field.dart';
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
    children: [
      FilledButton(
        style: BrandTheme.dangerButton,
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(action),
      ),
      const SizedBox(height: 8),
      _CancelButton(onPressed: () => Navigator.of(context).pop(false)),
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
    children: [
      FilledButton(
        style: BrandTheme.primaryButton,
        onPressed: () => Navigator.of(context).pop(),
        child: Text(action),
      ),
    ],
  );
}

/// A bottom sheet that asks for one line of text, above the keyboard: a
/// title, what to enter, the field, [action] and «Отмена».
class PromptSheet extends StatefulWidget {
  const PromptSheet({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    required this.hint,
    required this.action,
    this.keyboardType,
  });

  final String title;
  final String body;
  final IconData icon;
  final String hint;
  final String action;
  final TextInputType? keyboardType;

  /// The text entered, or null when cancelled.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String body,
    required IconData icon,
    required String hint,
    required String action,
    TextInputType? keyboardType,
  }) => _showSheet<String>(
    context,
    PromptSheet(
      title: title,
      body: body,
      icon: icon,
      hint: hint,
      action: action,
      keyboardType: keyboardType,
    ),
  );

  @override
  State<PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<PromptSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_text.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: _SheetBody(
      title: widget.title,
      body: widget.body,
      children: [
        BrandTextField(
          icon: widget.icon,
          hint: widget.hint,
          controller: _text,
          autofocus: true,
          keyboardType: widget.keyboardType,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: BrandTheme.primaryButton,
          onPressed: _submit,
          child: Text(widget.action),
        ),
        const SizedBox(height: 8),
        _CancelButton(onPressed: () => Navigator.of(context).pop()),
      ],
    ),
  );
}

/// A bottom sheet that holds the screen while something finishes: a spinner
/// and [message]. It cannot be closed; remove its [route] when done.
class ProgressSheet extends StatelessWidget {
  const ProgressSheet({super.key, required this.message});

  final String message;

  /// Push it, then `removeRoute` it, since another route may open above.
  static Route<void> route(BuildContext context, String message) =>
      _sheetRoute<void>(
        context,
        ProgressSheet(message: message),
        dismissible: false,
      );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          BrandSpacing.page,
          32,
          BrandSpacing.page,
          20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: BrandColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(message, style: BrandText.body, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

Future<T?> _showSheet<T>(BuildContext context, Widget sheet) => Navigator.of(
  context,
  rootNavigator: true,
).push(_sheetRoute<T>(context, sheet));

/// Every sheet's surface: the mockups' color, corners and grabber, above the
/// tab bar.
ModalBottomSheetRoute<T> _sheetRoute<T>(
  BuildContext context,
  Widget sheet, {
  bool dismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return ModalBottomSheetRoute<T>(
    builder: (_) => sheet,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(context).scrimLabel,
    isScrollControlled: true,
    // A tall sheet, or one the keyboard lifts, stops below the status bar.
    useSafeArea: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    showDragHandle: dismissible,
    backgroundColor: BrandColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(BrandRadii.sheet),
      ),
    ),
  );
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: BrandTheme.quietButton,
    onPressed: onPressed,
    child: Text(AppLocalizations.of(context)!.buttonCancel),
  );
}

/// A sheet's title and text, centred, above its [children].
class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.body,
    required this.children,
  });

  final String title;
  final String body;
  final List<Widget> children;

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
          ...children,
        ],
      ),
    ),
  );
}
