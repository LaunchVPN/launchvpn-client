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

/// A sign-in through another service's page or sheet. [failure] is shown
/// under its button for any refusal the form has no text of its own for.
enum LoginProvider {
  apple(AccountError.appleFailed),
  telegram(AccountError.telegramFailed);

  const LoginProvider(this.failure);

  final AccountError failure;
}

/// Why the last sign-in with [provider] failed.
typedef ProviderFailure = ({LoginProvider provider, AccountError error});

final class LoginState {
  const LoginState({
    this.mode = LoginMode.create,
    this.submitting = false,
    this.signingIn,
    this.error,
    this.signedOut,
    this.providerError,
    this.signup,
  });

  final LoginMode mode;
  final bool submitting;

  /// Signing in with Apple's sheet, or with the code Telegram brought back.
  final LoginProvider? signingIn;

  bool get busy => submitting || signingIn != null;

  /// Why the last attempt failed, shown under the fields until the next one.
  final AccountError? error;

  /// Why the device signed out on its own, shown under the fields of the
  /// sign-in form it opens to until the next attempt.
  final ForcedSignOut? signedOut;

  /// Shown under the provider's button: its [LoginProvider.failure] unless
  /// the backend named the reason.
  final ProviderFailure? providerError;

  /// A signup waiting for the code from the email: «Проверьте почту» shows
  /// instead of the form.
  final PendingSignup? signup;
}

/// The «Вход» form. Signing in, by email, Apple or Telegram, adds the account's
/// subscription the way a system link does. Creating an account, or signing
/// in with an unconfirmed email, leads to the code from the email.
final class LoginController extends PageCubit<LoginState> {
  LoginController({required this._account, LoginMode mode = LoginMode.create})
    : super(LoginState(mode: mode)) {
    if (_account.data.takeForcedSignOut() case final reason?) {
      emit(LoginState(mode: LoginMode.signIn, signedOut: reason));
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

  /// A tap on [provider]'s button. Apple's sheet covers the form until the
  /// person signs in or closes it. Telegram's sign-in opens in the browser,
  /// and the form stays usable until the person comes back with its code;
  /// turning Telegram down, or tapping again, leaves the form as it is.
  Future<void> signInWith(LoginProvider provider) async {
    if (state.busy) return;
    switch (provider) {
      case LoginProvider.apple:
        emit(LoginState(mode: state.mode, signingIn: provider));
        await _reportingFailure(provider, () async {
          await _account.apple.login();
          emit(LoginState(mode: state.mode));
        });
      case LoginProvider.telegram:
        emit(LoginState(mode: state.mode));
        await _redeemTelegram(_account.telegram.openLogin());
    }
  }

  /// Signs in with the code [pending] brings back from Telegram.
  Future<void> _redeemTelegram(Future<TelegramCode> pending) =>
      _reportingFailure(LoginProvider.telegram, () async {
        final code = await pending;
        // Signed in meanwhile, or doing so by email or Apple: the code would
        // switch accounts.
        if (state.busy || _account.session.signedIn.value) return;
        emit(LoginState(mode: state.mode, signingIn: LoginProvider.telegram));
        await _account.telegram.exchangeLogin(code);
        emit(LoginState(mode: state.mode));
      });

  /// Runs [signIn] and shows why it failed under [provider]'s button. Turning
  /// the provider down only ends its progress.
  Future<void> _reportingFailure(
    LoginProvider provider,
    Future<void> Function() signIn,
  ) async {
    try {
      await signIn();
    } on AccountException catch (error) {
      if (error.error == AccountError.cancelled) {
        if (state.signingIn == provider) emit(LoginState(mode: state.mode));
        return;
      }
      _failed(provider, switch (error.error) {
        AccountError.accountBlocked ||
        AccountError.appNotAvailable ||
        AccountError.emailTaken ||
        AccountError.rateLimited => error.error,
        _ => provider.failure,
      });
    } catch (error) {
      ygLogger('${provider.name} sign-in failed (${error.runtimeType})');
      _failed(provider, provider.failure);
    }
  }

  /// Shows [error] under [provider]'s button, unless another sign-in is
  /// under way: a Telegram attempt left in the browser may fail late.
  void _failed(LoginProvider provider, AccountError error) {
    if (state.busy && state.signingIn != provider) return;
    emit(
      LoginState(
        mode: state.mode,
        providerError: (provider: provider, error: error),
      ),
    );
  }

  /// «Не та почта? Изменить»: back to the form, whose fields keep their text.
  void changeEmail() => emit(LoginState(mode: state.mode));
}
