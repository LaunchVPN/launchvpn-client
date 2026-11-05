/// Why an account request failed. Backend errors come from the `code` of its
/// `{"ok": false, "code": …}` answer, never from the message.
enum AccountError {
  invalidCredentials,
  emailNotVerified,
  accountBlocked,
  appNotAvailable,
  rateLimited,

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
    'invalid_token' => signedOut,
    _ => unexpected,
  };
}

final class AccountException implements Exception {
  const AccountException(this.error);

  final AccountError error;

  @override
  String toString() => 'AccountException(${error.name})';
}
