import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/error_text.dart';
import 'package:onexray/brand/login/code_controller.dart';
import 'package:onexray/brand/login/footer_link.dart';
import 'package:onexray/brand/shake.dart';
import 'package:onexray/brand/text_field.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/service.dart';

/// «Проверьте почту» below the title of «Вход»: the code from the email for
/// [signup], a resend once a minute and the way back to the form.
class EmailCodeView extends StatefulWidget {
  const EmailCodeView({
    super.key,
    required this.signup,
    required this.account,
    required this.onChangeEmail,
  });

  final PendingSignup signup;
  final AccountService account;

  /// «Не та почта? Изменить».
  final VoidCallback onChangeEmail;

  @override
  State<EmailCodeView> createState() => _EmailCodeViewState();
}

class _EmailCodeViewState extends State<EmailCodeView> {
  late final _controller = EmailCodeController(
    email: widget.account.email,
    signup: widget.signup,
  );
  final _code = TextEditingController();

  /// Counts wrong codes, each of which shakes the field.
  var _wrongCodes = 0;

  @override
  void dispose() {
    unawaited(_controller.close());
    _code.dispose();
    super.dispose();
  }

  void _verify() {
    if (_code.text.length != _codeLength || _controller.state.verifying) {
      return;
    }
    TextInput.finishAutofillContext();
    unawaited(_controller.verify(_code.text));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return BlocConsumer<EmailCodeController, EmailCodeState>(
      bloc: _controller,
      listenWhen: (before, after) =>
          before.verifying &&
          !after.verifying &&
          after.error == EmailCodeError.wrongCode,
      listener: (_, _) => setState(() => _wrongCodes++),
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.signup.trialAvailable
                ? l.codeBody(widget.signup.email)
                : l.codeBodyConfirm(widget.signup.email),
            style: BrandText.hint,
          ),
          const SizedBox(height: 24),
          Shake(
            trigger: _wrongCodes,
            child: AutofillGroup(
              child: BrandTextField(
                icon: LucideIcons.keyRound,
                hint: l.codeHint,
                controller: _code,
                enabled: !state.verifying,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                // A pasted «123 456» or «Код: 123456» keeps only its digits.
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_codeLength),
                ],
                onSubmitted: (_) => _verify(),
              ),
            ),
          ),
          ErrorReveal(switch (state.error) {
            null => null,
            final error => _errorMessage(l, error, state.attemptsLeft),
          }),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: _code,
            builder: (_, _) => FilledButton(
              style: BrandTheme.primaryButton,
              onPressed: _code.text.length == _codeLength && !state.verifying
                  ? _verify
                  : null,
              child: ButtonProgress(
                busy: state.verifying,
                child: Text(l.codeSubmit),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            style: BrandTheme.linkButton,
            onPressed: state.canResend ? _controller.resend : null,
            child: Text(
              state.resendIn == Duration.zero
                  ? l.codeResend
                  : l.codeResendIn(_minutes(state.resendIn)),
            ),
          ),
          const SizedBox(height: 12),
          LoginFooterLink(
            question: l.codeWrongEmail,
            action: l.codeChangeEmail,
            onPressed: state.verifying ? null : widget.onChangeEmail,
          ),
        ],
      ),
    );
  }
}

const _codeLength = 6;

/// «0:42».
String _minutes(Duration wait) =>
    '${wait.inMinutes}:${(wait.inSeconds % 60).toString().padLeft(2, '0')}';

String _errorMessage(
  AppLocalizations l,
  EmailCodeError error,
  int? attemptsLeft,
) => switch (error) {
  EmailCodeError.wrongCode => switch (attemptsLeft) {
    final left? => l.codeErrorWrongLeft(left),
    null => l.codeErrorWrong,
  },
  EmailCodeError.codeExpired => l.codeErrorExpired,
  EmailCodeError.attemptGone => l.codeErrorAttemptGone,
  EmailCodeError.accountBlocked => l.loginErrorAccountBlocked,
  EmailCodeError.appNotAvailable => l.loginErrorAppNotAvailable,
  EmailCodeError.rateLimited => l.loginErrorRateLimited,
  EmailCodeError.network => l.loginErrorNetwork,
  EmailCodeError.unexpected => l.loginErrorUnexpected,
};
