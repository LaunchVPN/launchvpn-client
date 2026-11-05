import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/service.dart';

final class LoginState {
  const LoginState({this.submitting = false, this.error});

  final bool submitting;

  /// Why the last attempt failed, shown under the fields until the next one.
  final AccountError? error;
}

/// Signs in from «Вход». The account's subscription goes to [_openLink], the
/// queue system links also take, so it is added the same way.
final class LoginController extends PageCubit<LoginState> {
  LoginController({required this._account, required this._openLink})
    : super(const LoginState());

  final AccountService _account;
  final void Function(Uri) _openLink;

  Future<void> submit({required String email, required String password}) async {
    if (state.submitting) return;
    emit(const LoginState(submitting: true));
    try {
      final link = await _account.login(
        email: email.trim(),
        password: password,
      );
      if (link != null) _openLink(link);
      emit(const LoginState());
    } on AccountException catch (error) {
      emit(LoginState(error: error.error));
    } catch (error) {
      ygLogger('login failed (${error.runtimeType})');
      emit(const LoginState(error: AccountError.unexpected));
    }
  }
}
