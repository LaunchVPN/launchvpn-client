import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:url_launcher/url_launcher.dart';

/// What a trip through Telegram is for. The return names it as its `mode`;
/// signing in leaves it out.
enum TelegramAuthPurpose { login, link }

/// The one-time code a `launchvpn://auth` return brought, with the PKCE
/// verifier only this attempt knows.
final class TelegramCode {
  const TelegramCode({required this.code, required this.verifier});

  final String code;
  final String verifier;
}

/// Telegram's sign-in in the external browser, which hands back to the App
/// as `launchvpn://auth?code=…` or `?error=…` (PKCE for a custom scheme,
/// RFC 8252).
///
/// One attempt waits at a time and a new one replaces it. Its verifier lives
/// in memory only, so a return no attempt waits for, such as a repeat, one
/// after a restart or one for another purpose, is ignored.
final class TelegramBrowserAuth {
  TelegramBrowserAuth({
    Future<bool> Function(Uri url)? openBrowser,
    Random? random,
  }) : _openBrowser =
           openBrowser ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication)),
       _random = random ?? Random.secure();

  final Future<bool> Function(Uri url) _openBrowser;
  final Random _random;
  _Attempt? _pending;

  /// Whether [uri] is a return from the browser, whatever it carries.
  static bool isReturn(Uri uri) =>
      uri.scheme.toLowerCase() == Brand.scheme &&
      uri.host.toLowerCase() == Brand.authLinkHost;

  /// Opens the page [start] makes for the PKCE challenge and completes with
  /// the code once the browser returns for [purpose]. Throws
  /// [AccountException]: [AccountError.cancelled] when the person declined or
  /// started another attempt, otherwise the error the return named.
  Future<TelegramCode> authorize(
    TelegramAuthPurpose purpose,
    FutureOr<Uri> Function(String challenge) start,
  ) async {
    final attempt = _Attempt(purpose, _verifier());
    _pending?.fail(AccountError.cancelled);
    _pending = attempt;
    try {
      final url = await start(_challenge(attempt.verifier));
      if (!await _open(url)) {
        throw const AccountException(AccountError.unexpected);
      }
    } catch (_) {
      if (identical(_pending, attempt)) _pending = null;
      rethrow;
    }
    return attempt.result.future;
  }

  /// Hands a browser return to the attempt waiting for it. False, and nothing
  /// happens, when none waits for its purpose.
  bool handleReturn(Uri uri) {
    final attempt = _pending;
    if (attempt == null ||
        !isReturn(uri) ||
        TelegramAuthPurpose.values.asNameMap()[uri.queryParameters['mode'] ??
                TelegramAuthPurpose.login.name] !=
            attempt.purpose) {
      return false;
    }
    _pending = null;
    final code = uri.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      attempt.result.complete(
        TelegramCode(code: code, verifier: attempt.verifier),
      );
    } else {
      attempt.fail(AccountError.fromCode(uri.queryParameters['error']));
    }
    return true;
  }

  Future<bool> _open(Uri url) async {
    try {
      return await _openBrowser(url);
    } catch (error) {
      ygLogger('open Telegram sign-in failed (${error.runtimeType})');
      return false;
    }
  }

  /// 32 random bytes as base64url: 43 characters, RFC 7636's minimum.
  String _verifier() =>
      _base64Url([for (var i = 0; i < 32; i++) _random.nextInt(256)]);

  static String _challenge(String verifier) =>
      _base64Url(sha256.convert(ascii.encode(verifier)).bytes);

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}

final class _Attempt {
  _Attempt(this.purpose, this.verifier);

  final TelegramAuthPurpose purpose;
  final String verifier;
  final result = Completer<TelegramCode>();

  void fail(AccountError error) =>
      result.completeError(AccountException(error));
}
