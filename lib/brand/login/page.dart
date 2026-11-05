import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/login/controller.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/text_field.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';

/// «Вход», in place of the tabs while the device has neither a session nor a
/// subscription. Both sign-in and a pasted link hand their subscription to
/// [openLink], the queue incoming links go through.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.account, required this.openLink});

  final AccountService account;
  final void Function(Uri) openLink;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _login = LoginController(
    account: widget.account,
    openLink: widget.openLink,
  );
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    unawaited(_login.close());
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSubmit) return;
    TextInput.finishAutofillContext();
    unawaited(_login.submit(email: _email.text, password: _password.text));
  }

  bool get _canSubmit =>
      !_login.state.submitting &&
      _email.text.trim().isNotEmpty &&
      _password.text.isNotEmpty;

  Future<void> _addLink() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _SubscriptionLinkDialog(),
    );
    if (text == null || !mounted) return;
    final pasted = Uri.tryParse(text.trim());
    final link = pasted?.scheme == Brand.scheme
        ? pasted
        : SubscriptionDeepLink.fromUrl(text)?.uri;
    if (link == null) {
      ContextAlert.showToast(
        context,
        AppLocalizations.of(context)!.subscriptionLinkInvalid,
      );
      return;
    }
    widget.openLink(link);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnnotatedRegion(
      value: BrandTheme.statusBar,
      child: Scaffold(
        backgroundColor: BrandColors.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              BrandSpacing.page,
              48,
              BrandSpacing.page,
              BrandSpacing.page,
            ),
            child: AutofillGroup(
              child: BlocBuilder<LoginController, LoginState>(
                bloc: _login,
                builder: (context, state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _MarkTile(),
                    ),
                    const SizedBox(height: 36),
                    Text(l.loginTitle, style: BrandText.heroTitle),
                    const SizedBox(height: 36),
                    BrandTextField(
                      icon: LucideIcons.mail,
                      hint: l.loginEmail,
                      controller: _email,
                      enabled: !state.submitting,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 12),
                    BrandTextField(
                      icon: LucideIcons.lock,
                      hint: l.loginPassword,
                      controller: _password,
                      enabled: !state.submitting,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                    ),
                    if (state.error case final error?) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _errorMessage(l, error),
                          style: BrandText.caption.copyWith(
                            color: BrandColors.danger,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ListenableBuilder(
                      listenable: Listenable.merge([_email, _password]),
                      builder: (_, _) => FilledButton(
                        style: BrandTheme.primaryButton,
                        onPressed: _canSubmit ? _submit : null,
                        child: ButtonProgress(
                          busy: state.submitting,
                          child: Text(l.loginSubmit),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      style: BrandTheme.quietButton,
                      onPressed: state.submitting ? null : _addLink,
                      icon: const Icon(LucideIcons.link),
                      label: Text(l.loginHaveLink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _errorMessage(AppLocalizations l, AccountError error) => switch (error) {
  AccountError.invalidCredentials => l.loginErrorInvalidCredentials,
  AccountError.emailNotVerified => l.loginErrorEmailNotVerified,
  AccountError.rateLimited => l.loginErrorRateLimited,
  AccountError.network => l.loginErrorNetwork,
  AccountError.accountBlocked ||
  AccountError.appNotAvailable ||
  AccountError.signedOut ||
  AccountError.unexpected => l.loginErrorUnexpected,
};

/// The app icon from the mockup: the mark on an accent tile.
class _MarkTile extends StatelessWidget {
  const _MarkTile();

  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    height: 64,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: BrandColors.accentSoft,
      border: Border.all(color: BrandColors.accent),
      borderRadius: BorderRadius.circular(BrandRadii.card),
    ),
    child: const LaunchMark.tile(color: BrandColors.accent),
  );
}

/// Asks for a subscription link and pops with the text, or null.
class _SubscriptionLinkDialog extends StatefulWidget {
  const _SubscriptionLinkDialog();

  @override
  State<_SubscriptionLinkDialog> createState() =>
      _SubscriptionLinkDialogState();
}

class _SubscriptionLinkDialogState extends State<_SubscriptionLinkDialog> {
  final _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _add() => Navigator.of(context).pop(_link.text);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: BrandColors.surface,
      title: Text(l.loginLinkTitle, style: BrandText.cardTitle),
      content: BrandTextField(
        icon: LucideIcons.link,
        hint: l.loginLinkHint,
        controller: _link,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _add(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.buttonCancel),
        ),
        TextButton(onPressed: _add, child: Text(l.loginLinkAdd)),
      ],
    );
  }
}
