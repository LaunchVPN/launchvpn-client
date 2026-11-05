import 'dart:async';

import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/account/telegram_auth.dart';

/// What the «Вход» form does: create an account, as the mockup opens, or
/// sign in to one.
enum LoginMode { create, signIn }

final class LoginState {
  const LoginState({
    this.mode = LoginMode.create,
    this.submitting = false,
    this.redeemingTelegram = false,
    this.error,
    this.telegramError,
    this.signup,
  });

  final LoginMode mode;
  final bool submitting;

  /// Back from Telegram, the App is signing in with the code it brought.
  final bool redeemingTelegram;

  bool get busy => submitting || redeemingTelegram;

  /// Why the last attempt failed, shown under the fields until the next one.
  /// [AccountError.signedOut] when «Удалить аккаунт» found the session gone
  /// and the form opens to sign in again for it.
  final AccountError? error;

  /// Why the last Telegram sign-in failed, shown under its button:
  /// [AccountError.telegramFailed] unless the backend named the reason.
  final AccountError? telegramError;

  /// A signup waiting for the code from the email: «Проверьте почту» shows
  /// instead of the form.
  final PendingSignup? signup;
}

/// The «Вход» form. Signing in, by email or Telegram, adds the account's
/// subscription the way a system link does. Creating an account, or signing
/// in with an unconfirmed email, leads to the code from the email.
final class LoginController extends PageCubit<LoginState> {
  LoginController({required this._account, LoginMode mode = LoginMode.create})
    : super(LoginState(mode: mode)) {
    if (_account.data.takeUnfinishedDeletion()) {
      emit(
        const LoginState(mode: LoginMode.signIn, error: AccountError.signedOut),
      );
    }
    // A Telegram sign-in the system closed the App during.
    if (_account.telegram.browser.resume(TelegramAuthPurpose.login)
        case final code?) {
      unawaited(_redeemTelegram(code));
    }
  }

  final AccountService _account;

  void switchMode() {
    if (state.busy) return;
    emit(
      LoginState(
        mode: state.mode == LoginMode.create
            ? LoginMode.signIn
            : LoginMode.create,
      ),
    );
  }

  Future<void> submit({required String email, required String password}) async {
    if (state.busy) return;
    final mode = state.mode;
    emit(LoginState(mode: mode, submitting: true));
    try {
      switch (mode) {
        case LoginMode.create:
          final signup = await _account.email.signup(
            email: email.trim(),
            password: password,
          );
          emit(LoginState(mode: mode, signup: signup));
        case LoginMode.signIn:
          await _account.email.login(email: email.trim(), password: password);
          emit(LoginState(mode: mode));
      }
    } on AccountException catch (error) {
      emit(
        error.signup == null
            ? LoginState(mode: mode, error: error.error)
            : LoginState(mode: mode, signup: error.signup),
      );
    } catch (error) {
      ygLogger('${mode.name} failed (${error.runtimeType})');
      emit(LoginState(mode: mode, error: AccountError.unexpected));
    }
  }

  /// «Войти через Telegram»: Telegram's sign-in opens in the browser, and the
  /// form stays usable until the person comes back with its code. Turning
  /// Telegram down, or tapping again, leaves the form as it is.
  Future<void> signInWithTelegram() async {
    if (state.busy) return;
    emit(LoginState(mode: state.mode));
    await _redeemTelegram(_account.telegram.openLogin());
  }

  /// Signs in with the code [pending] brings back from Telegram.
  Future<void> _redeemTelegram(Future<TelegramCode> pending) async {
    try {
      final code = await pending;
      emit(LoginState(mode: state.mode, redeemingTelegram: true));
      await _account.telegram.exchangeLogin(code);
      emit(LoginState(mode: state.mode));
    } on AccountException catch (error) {
      if (error.error == AccountError.cancelled) return;
      emit(
        LoginState(
          mode: state.mode,
          telegramError: switch (error.error) {
            AccountError.accountBlocked ||
            AccountError.appNotAvailable => error.error,
            _ => AccountError.telegramFailed,
          },
        ),
      );
    } catch (error) {
      ygLogger('Telegram sign-in failed (${error.runtimeType})');
      emit(
        LoginState(
          mode: state.mode,
          telegramError: AccountError.telegramFailed,
        ),
      );
    }
  }

  /// «Не та почта? Изменить»: back to the form, whose fields keep their text.
  void changeEmail() => emit(LoginState(mode: state.mode));
}
