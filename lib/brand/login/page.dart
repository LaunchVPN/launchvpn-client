import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/login/code_view.dart';
import 'package:onexray/brand/login/controller.dart';
import 'package:onexray/brand/login/footer_link.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/shader_backdrop.dart';
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
/// subscription. It creates an account, as it opens by default, or signs in;
/// a new account, or an unconfirmed email, continues to «Проверьте почту» on
/// the same page. On Android it also signs in with Telegram. Sign-in, the
/// code and a pasted link hand their subscription to [openLink], the queue
/// incoming links go through.
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.account,
    required this.openLink,
    this.mode = LoginMode.create,
  });

  final AccountService account;
  final void Function(Uri) openLink;
  final LoginMode mode;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _login = LoginController(
    account: widget.account,
    openLink: widget.openLink,
    mode: widget.mode,
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
      !_login.state.busy &&
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
      child: ShaderBackdrop(
        child: BlocBuilder<LoginController, LoginState>(
          bloc: _login,
          builder: (context, state) {
            final signup = state.signup;
            return PopScope(
              // Back from the code returns to the form, as «Изменить» does.
              canPop: signup == null,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _login.changeEmail();
              },
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      BrandSpacing.page,
                      48,
                      BrandSpacing.page,
                      BrandSpacing.page,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _MarkTile(),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          signup == null ? l.loginTitle : l.codeTitle,
                          style: BrandText.heroTitle,
                        ),
                        const SizedBox(height: 12),
                        if (signup == null)
                          _form(l, state)
                        else
                          EmailCodeView(
                            key: ValueKey(signup),
                            signup: signup,
                            account: widget.account,
                            openLink: widget.openLink,
                            onChangeEmail: _login.changeEmail,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l, LoginState state) {
    final creates = state.mode == LoginMode.create;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (creates) Text(l.loginCreateSubtitle, style: BrandText.hint),
          const SizedBox(height: 24),
          BrandTextField(
            icon: LucideIcons.mail,
            hint: l.loginEmail,
            controller: _email,
            enabled: !state.busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 12),
          BrandTextField(
            icon: LucideIcons.lock,
            hint: l.loginPassword,
            controller: _password,
            enabled: !state.busy,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: [
              if (creates)
                AutofillHints.newPassword
              else
                AutofillHints.password,
            ],
            onSubmitted: (_) => _submit(),
          ),
          if (state.error case final error?) ...[
            const SizedBox(height: 12),
            _ErrorText(_errorMessage(l, error)),
          ],
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: Listenable.merge([_email, _password]),
            builder: (_, _) => FilledButton(
              style: BrandTheme.primaryButton,
              onPressed: _canSubmit ? _submit : null,
              child: ButtonProgress(
                busy: state.submitting,
                child: Text(creates ? l.loginCreate : l.loginSubmit),
              ),
            ),
          ),
          // Not on iOS: App Store guideline 4.8 would then require Sign in
          // with Apple.
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            const SizedBox(height: 16),
            _OrDivider(l.loginOr),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: BrandTheme.secondaryButton,
              onPressed: state.busy
                  ? null
                  : () => unawaited(_login.signInWithTelegram()),
              icon: const Icon(LucideIcons.send),
              label: ButtonProgress(
                busy: state.redeemingTelegram,
                child: Text(l.loginTelegram),
              ),
            ),
            if (state.telegramError case final error?) ...[
              const SizedBox(height: 12),
              _ErrorText(_errorMessage(l, error)),
            ],
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            style: BrandTheme.quietButton,
            onPressed: state.busy ? null : _addLink,
            icon: const Icon(LucideIcons.link),
            label: Text(l.loginHaveLink),
          ),
          const SizedBox(height: 12),
          LoginFooterLink(
            question: creates ? l.loginHaveAccount : l.loginNoAccount,
            action: creates ? l.loginSubmit : l.loginToCreate,
            onPressed: state.busy ? null : _login.switchMode,
          ),
        ],
      ),
    );
  }
}

String _errorMessage(AppLocalizations l, AccountError error) => switch (error) {
  AccountError.invalidCredentials => l.loginErrorInvalidCredentials,
  AccountError.emailNotVerified => l.loginErrorEmailNotVerified,
  AccountError.rateLimited => l.loginErrorRateLimited,
  AccountError.emailTaken => l.loginErrorEmailTaken,
  AccountError.invalidRequest => l.loginErrorInvalidRequest,
  AccountError.network => l.loginErrorNetwork,
  AccountError.telegramFailed => l.loginErrorTelegram,
  AccountError.accountBlocked => l.loginErrorAccountBlocked,
  AccountError.appNotAvailable => l.loginErrorAppNotAvailable,
  AccountError.signedOut => l.loginErrorSignInToDelete,
  AccountError.invalidCode ||
  AccountError.codeExpired ||
  AccountError.trialUsed ||
  AccountError.cancelled ||
  AccountError.telegramTaken ||
  AccountError.alreadyLinked ||
  AccountError.unexpected => l.loginErrorUnexpected,
};

/// Why the last attempt failed, read out when it appears.
class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: BrandText.caption.copyWith(color: BrandColors.danger),
    ),
  );
}

/// «или» between the form and the Telegram sign-in.
class _OrDivider extends StatelessWidget {
  const _OrDivider(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider(color: BrandColors.line)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label, style: BrandText.hint),
      ),
      const Expanded(child: Divider(color: BrandColors.line)),
    ],
  );
}

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
