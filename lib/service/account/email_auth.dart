import 'package:onexray/service/account/account_data.dart';
import 'package:onexray/service/account/device_claim.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/session.dart';

/// Signing in by email and password, and signing up with the code the
/// backend mails.
final class EmailAuth {
  EmailAuth({
    required this._session,
    required this._data,
    required this._device,
    required this._language,
  });

  final AccountSession _session;

  /// Finishes a sign-in with the account's subscription.
  final AccountData _data;
  final Future<DeviceClaim> Function() _device;

  /// The App's language, `ru` or `en`, for the emails the backend sends.
  final String Function() _language;

  /// Signs in and adds the account's subscription, unless it has none or it
  /// could not be read. Throws [AccountException] when the sign-in itself
  /// fails; for an unconfirmed email it carries the [PendingSignup] the
  /// backend mailed a code for.
  Future<void> login({required String email, required String password}) async {
    final device = await _device();
    await _data.signIn(
      await _session.post(
        '/api/app/auth/login',
        data: {
          'email': email,
          'password': password,
          ...device.toJson(),
          'deviceModel': ?device.model,
        },
        email: email,
      ),
    );
  }

  /// Creates the account, or a new attempt for an unconfirmed one, and has a
  /// code mailed. Nothing is signed in until [verifyCode].
  Future<PendingSignup> signup({
    required String email,
    required String password,
  }) async {
    final device = await _device();
    final data = await _session.post(
      '/api/app/auth/signup',
      data: {
        'email': email,
        'password': password,
        ...device.toJson(),
        'language': _language(),
      },
    );
    final token = data['signupToken'];
    if (token is! String || token.isEmpty) {
      throw const AccountException(AccountError.unexpected);
    }
    return PendingSignup(
      email: email,
      token: token,
      resendIn: PendingSignup.waitIn(data),
      trialAvailable: PendingSignup.trialIn(data),
    );
  }

  /// Confirms [signup] with the mailed [code], signs in and adds the
  /// account's subscription as [login] does.
  Future<void> verifyCode(PendingSignup signup, String code) async {
    final device = await _device();
    await _data.signIn(
      await _session.post(
        '/api/app/auth/verify-code',
        data: {
          'email': signup.email,
          'code': code,
          'signupToken': signup.token,
          ...device.toJson(),
        },
      ),
    );
  }

  /// Mails a new code for [signup] and returns the wait before the next.
  Future<Duration> resendCode(PendingSignup signup) async =>
      PendingSignup.waitIn(
        await _session.post(
          '/api/app/auth/resend-code',
          data: {'signupToken': signup.token, 'language': _language()},
        ),
      );
}
