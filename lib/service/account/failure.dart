import 'package:dio/dio.dart';
import 'package:onexray/service/account/model.dart';

/// Why an account request failed. Backend errors come from the `code` of its
/// `{"ok": false, "code": …}` answer, never from the message.
enum AccountError {
  invalidCredentials,
  emailNotVerified,
  accountBlocked,
  appNotAvailable,
  rateLimited,

  /// Signup: the email already has a confirmed account.
  emailTaken,

  /// The email or the password breaks the site's rules.
  invalidRequest,

  /// A wrong code from the email; [AccountException.attemptsLeft] says how
  /// many tries it has left.
  invalidCode,

  /// The code expired or was burned, or the signup attempt itself is gone.
  codeExpired,

  /// The account or this device already had its trial.
  trialUsed,

  /// The person turned Telegram's sign-in down, or started another one.
  cancelled,

  /// Telegram's sign-in did not finish in the browser.
  telegramFailed,

  /// Linking: that Telegram belongs to another account with an email.
  telegramTaken,

  /// Linking: the account has Telegram already.
  alreadyLinked,

  /// The backend could not be reached.
  network,

  /// The device session ended: no tokens, or the backend refused the refresh.
  signedOut,

  /// Anything else, including a malformed answer.
  unexpected;

  static AccountError fromCode(Object? code) => switch (code) {
    'invalid_credentials' => invalidCredentials,
    'email_not_verified' => emailNotVerified,
    'account_blocked' => accountBlocked,
    'app_not_available' => appNotAvailable,
    'rate_limited' => rateLimited,
    'email_taken' => emailTaken,
    'invalid_request' => invalidRequest,
    'invalid_code' => invalidCode,
    'code_expired' => codeExpired,
    'trial_used' => trialUsed,
    'cancelled' => cancelled,
    'telegram_failed' => telegramFailed,
    'telegram_taken' => telegramTaken,
    'already_linked' => alreadyLinked,
    'invalid_token' => signedOut,
    _ => unexpected,
  };
}

final class AccountException implements Exception {
  const AccountException(
    this.error, {
    this.attemptsLeft,
    this.retryAfter,
    this.signup,
  });

  final AccountError error;

  /// With [AccountError.invalidCode].
  final int? attemptsLeft;

  /// With [AccountError.rateLimited] on a resend: when the next code may go.
  final Duration? retryAfter;

  /// With [AccountError.emailNotVerified] on login: the backend mailed a code
  /// for this attempt.
  final PendingSignup? signup;

  /// What a failed request stands for. A sign-in names its [email] so an
  /// unconfirmed one can continue to the code.
  static AccountException fromDio(DioException error, {String? email}) {
    final cause = error.error;
    if (cause is AccountException) return cause;
    final response = error.response;
    if (response == null) {
      return error.type == DioExceptionType.cancel
          ? const AccountException(AccountError.unexpected)
          : const AccountException(AccountError.network);
    }
    final data = response.data;
    if (data is! Map) return const AccountException(AccountError.unexpected);
    final token = data['signupToken'];
    return AccountException(
      AccountError.fromCode(data['code']),
      attemptsLeft: switch (data['attemptsLeft']) {
        final int left => left,
        _ => null,
      },
      retryAfter: data.containsKey('retryAfter')
          ? PendingSignup.waitIn(data)
          : null,
      signup: email != null && token is String && token.isNotEmpty
          ? PendingSignup(
              email: email,
              token: token,
              resendIn: PendingSignup.resendGap,
              trialAvailable: PendingSignup.trialIn(data),
              trialDays: PendingSignup.trialDaysIn(data),
            )
          : null,
    );
  }

  @override
  String toString() => 'AccountException(${error.name})';
}
