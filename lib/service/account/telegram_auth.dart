import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
/// One attempt waits at a time and a new one replaces it. A return no
/// attempt waits for, such as a repeat or one for another purpose, is
/// ignored. The waiting attempt is also kept in the secure store, so one the
/// system closed the App during survives the restart for [_lifetime]:
/// [restore] picks it up and whoever started it takes it back with [resume].
final class TelegramBrowserAuth {
  TelegramBrowserAuth({
    Future<bool> Function(Uri url)? openBrowser,
    Random? random,
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  }) : _openBrowser =
           openBrowser ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication)),
       _random = random ?? Random.secure(),
       _storage =
           storage ??
           const FlutterSecureStorage(
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
           ),
       _now = now ?? DateTime.now;

  final Future<bool> Function(Uri url) _openBrowser;
  final Random _random;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  _Attempt? _pending;

  /// Restored by [restore] and not yet taken back by [resume].
  _Attempt? _restored;

  static const _key = 'account.telegram';

  /// How long an attempt outlives the App. Telegram's page and the code it
  /// returns expire well before.
  static const _lifetime = Duration(minutes: 10);

  /// Whether [uri] is a return from the browser, whatever it carries.
  static bool isReturn(Uri uri) =>
      uri.scheme.toLowerCase() == Brand.scheme &&
      uri.host.toLowerCase() == Brand.authLinkHost;

  /// What the return [uri] is for; null for a mode the App does not know.
  static TelegramAuthPurpose? purposeOf(Uri uri) =>
      TelegramAuthPurpose.values.asNameMap()[uri.queryParameters['mode'] ??
          TelegramAuthPurpose.login.name];

  /// Opens the page [start] makes for the PKCE challenge and completes with
  /// the code once the browser returns for [purpose]. Throws
  /// [AccountException]: [AccountError.cancelled] when the person declined or
  /// started another attempt, otherwise the error the return named.
  Future<TelegramCode> authorize(
    TelegramAuthPurpose purpose,
    FutureOr<Uri> Function(String challenge) start,
  ) async {
    final attempt = _Attempt(purpose, _verifier(), _now());
    _pending?.fail(AccountError.cancelled);
    _pending = attempt;
    _restored = null;
    // A newer attempt that started meanwhile owns the store and the browser.
    void ensureCurrent() {
      if (!identical(_pending, attempt)) {
        throw const AccountException(AccountError.cancelled);
      }
    }

    try {
      final url = await start(_challenge(attempt.verifier));
      ensureCurrent();
      // Saved before the browser opens: the App may not see it close.
      await _save(attempt);
      ensureCurrent();
      if (!await _open(url)) {
        throw const AccountException(AccountError.unexpected);
      }
    } catch (_) {
      if (identical(_pending, attempt)) {
        _pending = null;
        unawaited(_forget());
      }
      rethrow;
    }
    return attempt.result.future;
  }

  /// Picks up the attempt an earlier launch left waiting, unless it is older
  /// than [_lifetime] or another one has started since.
  Future<void> restore() async {
    final saved = await _read();
    if (saved == null || _pending != null) return;
    if (_now().difference(saved.startedAt) > _lifetime) return _forget();
    _pending = _restored = saved;
  }

  /// The attempt for [purpose] [restore] found, to complete as if it had
  /// just been started; null when there is none. It is handed out once.
  Future<TelegramCode>? resume(TelegramAuthPurpose purpose) {
    final restored = _restored;
    if (restored == null || restored.purpose != purpose) return null;
    _restored = null;
    return restored.result.future;
  }

  /// Whether [restore] found an attempt for [purpose] nobody took back yet.
  bool awaitsResume(TelegramAuthPurpose purpose) =>
      _restored?.purpose == purpose;

  /// Hands a browser return to the attempt waiting for it. False, and nothing
  /// happens, when none waits for its purpose.
  bool handleReturn(Uri uri) {
    final attempt = _pending;
    if (attempt == null ||
        !isReturn(uri) ||
        purposeOf(uri) != attempt.purpose) {
      return false;
    }
    _pending = null;
    unawaited(_forget());
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

  /// A failing store leaves the attempt in memory only.
  Future<void> _save(_Attempt attempt) async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'purpose': attempt.purpose.name,
          'verifier': attempt.verifier,
          'startedAt': attempt.startedAt.millisecondsSinceEpoch,
        }),
      );
    } catch (error) {
      ygLogger('save Telegram attempt failed (${error.runtimeType})');
    }
  }

  Future<_Attempt?> _read() async {
    try {
      final saved = await _storage.read(key: _key);
      if (saved == null) return null;
      if (jsonDecode(saved) case {
        'purpose': final String purpose,
        'verifier': final String verifier,
        'startedAt': final int startedAt,
      }) {
        if (TelegramAuthPurpose.values.asNameMap()[purpose] case final kind?) {
          return _Attempt(
            kind,
            verifier,
            DateTime.fromMillisecondsSinceEpoch(startedAt),
          );
        }
      }
    } catch (error) {
      ygLogger('read Telegram attempt failed (${error.runtimeType})');
    }
    await _forget();
    return null;
  }

  Future<void> _forget() async {
    try {
      await _storage.delete(key: _key);
    } catch (error) {
      ygLogger('forget Telegram attempt failed (${error.runtimeType})');
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
  /// [result] may fail with nobody waiting: a restored attempt nobody takes
  /// back, or one a newer attempt replaced before it was handed out.
  _Attempt(this.purpose, this.verifier, this.startedAt) {
    result.future.ignore();
  }

  final TelegramAuthPurpose purpose;
  final String verifier;
  final DateTime startedAt;
  final result = Completer<TelegramCode>();

  void fail(AccountError error) =>
      result.completeError(AccountException(error));
}
