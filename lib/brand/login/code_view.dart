import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/login/code_controller.dart';
import 'package:onexray/brand/login/footer_link.dart';
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
    required this.openLink,
    required this.onChangeEmail,
  });

  final PendingSignup signup;
  final AccountService account;
  final void Function(Uri) openLink;

  /// «Не та почта? Изменить».
  final VoidCallback onChangeEmail;

  @override
  State<EmailCodeView> createState() => _EmailCodeViewState();
}

class _EmailCodeViewState extends State<EmailCodeView> {
  late final _controller = EmailCodeController(
    account: widget.account,
    openLink: widget.openLink,
    signup: widget.signup,
  );
  final _code = TextEditingController();

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
    return BlocBuilder<EmailCodeController, EmailCodeState>(
      bloc: _controller,
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.codeBody(widget.signup.email), style: BrandText.hint),
          const SizedBox(height: 24),
          AutofillGroup(
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
          if (state.error case final error?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _errorMessage(l, error, state.attemptsLeft),
                style: BrandText.caption.copyWith(color: BrandColors.danger),
              ),
            ),
          ],
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
  EmailCodeError.rateLimited => l.loginErrorRateLimited,
  EmailCodeError.network => l.loginErrorNetwork,
  EmailCodeError.unexpected => l.loginErrorUnexpected,
};
