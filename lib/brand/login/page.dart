import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/error_text.dart';
import 'package:onexray/brand/login/code_view.dart';
import 'package:onexray/brand/login/controller.dart';
import 'package:onexray/brand/login/footer_link.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/shader_backdrop.dart';
import 'package:onexray/brand/swap.dart';
import 'package:onexray/brand/text_field.dart';
import 'package:onexray/brand/sheet.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/toast.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/shared/share/service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show AppleLogoPainter;

/// «Вход», in place of the tabs while the device has neither a session nor a
/// subscription. It creates an account, as it opens by default, or signs in;
/// a new account, or an unconfirmed email, continues to «Проверьте почту» on
/// the same page. On iOS it also signs in with Apple and Telegram, on Android
/// with Telegram. A pasted link goes to [links], the queue incoming links go
/// through.
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.account,
    this.mode = LoginMode.create,
    this.links,
  });

  final AccountService account;
  final LoginMode mode;

  /// [ShareService]'s own when null.
  final ShareService? links;

  /// «Вход» over the tabs in [mode], closed by the sign-in it exists for:
  /// the first true from [signedIn]. On top it leaves as it came, with the
  /// route's own transition.
  static Future<void> showOverTabs(
    BuildContext context, {
    required AccountService account,
    required LoginMode mode,
    required Stream<bool> signedIn,
    ShareService? links,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = MaterialPageRoute<void>(
      builder: (_) => LoginPage(account: account, mode: mode, links: links),
    );
    final closing = signedIn.where((value) => value).listen((_) {
      if (route.isCurrent) {
        navigator.pop();
      } else if (route.isActive) {
        navigator.removeRoute(route);
      }
    });
    try {
      await navigator.push(route);
    } finally {
      await closing.cancel();
    }
  }

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _login = LoginController(
    account: widget.account,
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
    final l = AppLocalizations.of(context)!;
    final text = await PromptSheet.show(
      context,
      title: l.loginLinkTitle,
      body: l.loginLinkBody,
      icon: LucideIcons.link,
      hint: l.loginLinkHint,
      action: l.loginLinkAdd,
      keyboardType: TextInputType.url,
    );
    if (text == null || !mounted) return;
    final link = SubscriptionDeepLink.pasted(text);
    if (link == null) {
      showBrandToast(context, l.subscriptionLinkInvalid, kind: ToastKind.error);
      return;
    }
    (widget.links ?? ShareService()).addAppLink(link);
  }

  /// The sign-ins «Вход» offers below the form on this platform. Apple's
  /// comes only on iOS, where App Store guideline 4.8 asks for it next to
  /// Telegram's.
  static List<LoginProvider> get _providers => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => const [LoginProvider.apple, LoginProvider.telegram],
    TargetPlatform.android => const [LoginProvider.telegram],
    _ => const [],
  };

  void _signInWith(LoginProvider provider) => unawaited(switch (provider) {
    LoginProvider.apple => _login.signInWithApple(),
    LoginProvider.telegram => _login.signInWithTelegram(),
  });

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
                          child: LaunchMarkTile(),
                        ),
                        const SizedBox(height: 36),
                        // The code comes in from the end, the form from the
                        // start, each with its title.
                        BrandSwap(
                          shift: Offset(
                            signup == null
                                ? -BrandMotion.step
                                : BrandMotion.step,
                            0,
                          ),
                          duration: BrandMotion.fast,
                          curve: BrandMotion.smoothOut,
                          alignment: AlignmentDirectional.topStart,
                          child: Column(
                            key: ValueKey(signup == null),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                  onChangeEmail: _login.changeEmail,
                                ),
                            ],
                          ),
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
          ErrorText(_formMessage(l, state)),
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
          if (_providers case final providers when providers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _OrDivider(l.loginOr),
            for (final provider in providers) ...[
              const SizedBox(height: 16),
              _ProviderButton(
                provider,
                busy: state.redeeming == provider,
                onPressed: state.busy ? null : () => _signInWith(provider),
              ),
              ErrorText(switch (state.providerError) {
                (provider: final failed, :final error)
                    when failed == provider =>
                  _errorMessage(l, error),
                _ => null,
              }),
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

/// What shows under the fields: why the last attempt failed, or why the
/// device signed out on its own.
String? _formMessage(AppLocalizations l, LoginState state) => switch (state) {
  LoginState(error: final error?) => _errorMessage(l, error),
  LoginState(signedOut: ForcedSignOut.sessionEnded) => l.loginErrorSessionEnded,
  LoginState(signedOut: ForcedSignOut.deletionUnfinished) =>
    l.loginErrorSignInToDelete,
  LoginState() => null,
};

String _errorMessage(AppLocalizations l, AccountError error) => switch (error) {
  AccountError.invalidCredentials => l.loginErrorInvalidCredentials,
  AccountError.emailNotVerified => l.loginErrorEmailNotVerified,
  AccountError.rateLimited => l.loginErrorRateLimited,
  AccountError.emailTaken => l.loginErrorEmailTaken,
  AccountError.invalidRequest => l.loginErrorInvalidRequest,
  AccountError.network => l.loginErrorNetwork,
  AccountError.telegramFailed => l.loginErrorTelegram,
  AccountError.appleFailed => l.loginErrorApple,
  AccountError.accountBlocked => l.loginErrorAccountBlocked,
  AccountError.appNotAvailable => l.loginErrorAppNotAvailable,
  AccountError.signedOut => l.loginErrorSessionEnded,
  AccountError.invalidCode ||
  AccountError.codeExpired ||
  AccountError.trialUsed ||
  AccountError.cancelled ||
  AccountError.telegramTaken ||
  AccountError.alreadyLinked ||
  AccountError.unexpected => l.loginErrorUnexpected,
};

/// A sign-in through [provider], showing progress while it signs in.
/// Apple's keeps Apple's look, as its guidelines ask.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton(
    this.provider, {
    required this.busy,
    required this.onPressed,
  });

  final LoginProvider provider;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (style, icon, label) = switch (provider) {
      LoginProvider.apple => (
        BrandTheme.appleButton,
        const _AppleLogo(),
        l.loginApple,
      ),
      LoginProvider.telegram => (
        BrandTheme.secondaryButton,
        const Icon(LucideIcons.send),
        l.loginTelegram,
      ),
    };
    return FilledButton.icon(
      style: style,
      onPressed: onPressed,
      icon: icon,
      label: ButtonProgress(busy: busy, child: Text(label)),
    );
  }
}

/// Apple's logo at the button's icon size, in its text color.
class _AppleLogo extends StatelessWidget {
  const _AppleLogo();

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final size = icon.size ?? 20;
    return CustomPaint(
      size: Size(size * 25 / 31, size),
      painter: AppleLogoPainter(color: icon.color ?? Colors.black),
    );
  }
}

/// «или» between the form and the sign-ins through other services.
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

/// Asks for a subscription link and pops with the text, or null.
