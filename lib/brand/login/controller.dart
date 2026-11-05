import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/service.dart';

/// What the «Вход» form does: create an account, as the mockup opens, or
/// sign in to one.
enum LoginMode { create, signIn }

final class LoginState {
  const LoginState({
    this.mode = LoginMode.create,
    this.submitting = false,
    this.error,
    this.signup,
  });

  final LoginMode mode;
  final bool submitting;

  /// Why the last attempt failed, shown under the fields until the next one.
  final AccountError? error;

  /// A signup waiting for the code from the email: «Проверьте почту» shows
  /// instead of the form.
  final PendingSignup? signup;
}

/// The «Вход» form. Signing in hands the account's subscription to
/// [_openLink], the queue system links also take, so it is added the same
/// way. Creating an account, or signing in with an unconfirmed email, leads
/// to the code from the email.
final class LoginController extends PageCubit<LoginState> {
  LoginController({
    required this._account,
    required this._openLink,
    LoginMode mode = LoginMode.create,
  }) : super(LoginState(mode: mode));

  final AccountService _account;
  final void Function(Uri) _openLink;

  void switchMode() {
    if (state.submitting) return;
    emit(
      LoginState(
        mode: state.mode == LoginMode.create
            ? LoginMode.signIn
            : LoginMode.create,
      ),
    );
  }

  Future<void> submit({required String email, required String password}) async {
    if (state.submitting) return;
    final mode = state.mode;
    emit(LoginState(mode: mode, submitting: true));
    try {
      switch (mode) {
        case LoginMode.create:
          final signup = await _account.signup(
            email: email.trim(),
            password: password,
          );
          emit(LoginState(mode: mode, signup: signup));
        case LoginMode.signIn:
          final link = await _account.login(
            email: email.trim(),
            password: password,
          );
          if (link != null) _openLink(link);
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

  /// «Не та почта? Изменить»: back to the form, whose fields keep their text.
  void changeEmail() => emit(LoginState(mode: state.mode));
}
