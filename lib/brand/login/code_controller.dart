import 'dart:async';

import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/email_auth.dart';

/// What went wrong on «Проверьте почту», shown under the code field.
enum EmailCodeError {
  /// [EmailCodeState.attemptsLeft] says how many tries remain.
  wrongCode,

  /// The code expired or was burned: a new one fixes it.
  codeExpired,

  /// The signup attempt itself is gone: the form has to be sent again.
  attemptGone,
  accountBlocked,
  appNotAvailable,
  rateLimited,
  network,
  unexpected,
}

final class EmailCodeState {
  const EmailCodeState({
    required this.resendIn,
    this.verifying = false,
    this.resending = false,
    this.error,
    this.attemptsLeft,
  });

  /// Until another code may be sent; zero once it may.
  final Duration resendIn;
  final bool verifying;
  final bool resending;
  final EmailCodeError? error;

  /// With [EmailCodeError.wrongCode].
  final int? attemptsLeft;

  bool get canResend => resendIn == Duration.zero && !resending;

  EmailCodeState withResendIn(Duration resendIn) => EmailCodeState(
    resendIn: resendIn,
    verifying: verifying,
    resending: resending,
    error: error,
    attemptsLeft: attemptsLeft,
  );

  /// Nothing running any more, with [error] or none.
  EmailCodeState settled([EmailCodeError? error, int? attemptsLeft]) =>
      EmailCodeState(
        resendIn: resendIn,
        error: error,
        attemptsLeft: attemptsLeft,
      );
}

/// «Проверьте почту»: confirms [_signup] with the mailed code, which adds the
/// account's subscription as a sign-in does, and counts down to the next
/// resend.
final class EmailCodeController extends PageCubit<EmailCodeState> {
  EmailCodeController({required this._email, required this._signup})
    : super(EmailCodeState(resendIn: _signup.resendIn)) {
    _countFrom(_signup.resendIn);
  }

  final EmailAuth _email;
  final PendingSignup _signup;
  Timer? _countdown;

  String get email => _signup.email;

  Future<void> verify(String code) async {
    if (state.verifying) return;
    emit(EmailCodeState(resendIn: state.resendIn, verifying: true));
    try {
      await _email.verifyCode(_signup, code.trim());
      emit(state.settled());
    } on AccountException catch (error) {
      emit(
        state.settled(switch (error.error) {
          AccountError.invalidCode when (error.attemptsLeft ?? 1) > 0 =>
            EmailCodeError.wrongCode,
          AccountError.invalidCode ||
          AccountError.codeExpired => EmailCodeError.codeExpired,
          final other => _general(other),
        }, error.attemptsLeft),
      );
    } catch (error) {
      ygLogger('verify email code failed (${error.runtimeType})');
      emit(state.settled(EmailCodeError.unexpected));
    }
  }

  /// Mails a new code once the countdown is over.
  Future<void> resend() async {
    if (!state.canResend) return;
    emit(EmailCodeState(resendIn: state.resendIn, resending: true));
    try {
      _countFrom(await _email.resendCode(_signup));
      emit(state.settled());
    } on AccountException catch (error) {
      // Too early: the backend's wait replaces the countdown.
      if (error.retryAfter case final wait?) {
        _countFrom(wait);
        emit(state.settled());
        return;
      }
      emit(
        state.settled(switch (error.error) {
          AccountError.codeExpired => EmailCodeError.attemptGone,
          final other => _general(other),
        }),
      );
    } catch (error) {
      ygLogger('resend email code failed (${error.runtimeType})');
      emit(state.settled(EmailCodeError.unexpected));
    }
  }

  static EmailCodeError _general(AccountError error) => switch (error) {
    AccountError.accountBlocked => EmailCodeError.accountBlocked,
    AccountError.appNotAvailable => EmailCodeError.appNotAvailable,
    AccountError.rateLimited => EmailCodeError.rateLimited,
    AccountError.network => EmailCodeError.network,
    _ => EmailCodeError.unexpected,
  };

  void _countFrom(Duration wait) {
    _countdown?.cancel();
    emit(state.withResendIn(wait));
    if (wait <= Duration.zero) return;
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = state.resendIn - const Duration(seconds: 1);
      if (left <= Duration.zero) timer.cancel();
      emit(state.withResendIn(left < Duration.zero ? Duration.zero : left));
    });
  }

  @override
  Future<void> disposePageResources() async => _countdown?.cancel();
}
