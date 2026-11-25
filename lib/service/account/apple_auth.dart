import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:onexray/service/account/account_data.dart';
import 'package:onexray/service/account/device_claim.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/session.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// What Apple's sheet hands back for the backend to verify.
typedef AppleCredential = ({String identityToken, String authorizationCode});

/// Shows Apple's sheet for a request bound to [hashedNonce].
typedef AppleAuthorize = Future<AppleCredential> Function(String hashedNonce);

/// Signing in with Apple, on iOS. Apple's sheet signs a token bound to a
/// fresh nonce's hash; the backend checks it against the raw nonce, so a
/// token alone does not sign anyone in.
final class AppleAuth {
  AppleAuth({
    required this._session,
    required this._data,
    required this._device,
    AppleAuthorize? authorize,
    String Function()? nonce,
  }) : _authorize = authorize ?? _appleSheet,
       _nonce = nonce ?? generateNonce;

  final AccountSession _session;

  /// Finishes a sign-in with the account's subscription.
  final AccountData _data;
  final Future<DeviceClaim> Function() _device;
  final AppleAuthorize _authorize;
  final String Function() _nonce;

  /// Signs in or up through Apple's sheet and adds the account's
  /// subscription as an email sign-in does. Throws [AccountException]:
  /// [AccountError.cancelled] when the person closes the sheet.
  Future<void> login() async {
    final nonce = _nonce();
    final credential = await _authorize(
      sha256.convert(utf8.encode(nonce)).toString(),
    );
    final device = await _device();
    await _data.signIn(
      await _session.post(
        '/api/app/auth/apple',
        data: {
          'identityToken': credential.identityToken,
          'authorizationCode': credential.authorizationCode,
          'nonce': nonce,
          ...device.toJson(),
        },
      ),
    );
  }

  static Future<AppleCredential> _appleSheet(String hashedNonce) async {
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      throw AccountException(
        error.code == AuthorizationErrorCode.canceled
            ? AccountError.cancelled
            : AccountError.appleFailed,
      );
    } on SignInWithAppleException {
      throw const AccountException(AccountError.appleFailed);
    }
    return switch (credential.identityToken) {
      final String token => (
        identityToken: token,
        authorizationCode: credential.authorizationCode,
      ),
      null => throw const AccountException(AccountError.appleFailed),
    };
  }
}
