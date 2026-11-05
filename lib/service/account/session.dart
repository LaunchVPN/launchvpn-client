import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/session_store.dart';

/// How a request carries the session.
enum AccountAuth {
  /// Without it: signing in, signing up and the refresh itself.
  none,

  /// With the access token; a 401 refreshes it once, shared by every request
  /// waiting on it, and repeats the request once.
  bearer,

  /// With the access token, never repeated: for a request whose refusal
  /// burns what it carries.
  bearerOnce,
}

/// This device's session with the account API and the requests that carry
/// it. A refused refresh runs [onRevoked] and signs out; an outage keeps the
/// session for the next attempt. Tokens and response bodies are never logged.
final class AccountSession {
  AccountSession({
    required this._dio,
    required this._store,
    required this._onRevoked,
  }) {
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _authorize, onError: _refreshOnRefusal),
    );
  }

  final Dio _dio;
  final AccountSessionStore _store;

  /// Cleans up after the backend ended the session, before it ends here.
  final Future<void> Function() _onRevoked;
  final _signedIn = ValueNotifier(false);
  AccountTokens? _tokens;
  Future<AccountTokens?>? _refreshing;

  static const _auth = 'account.auth';

  ValueListenable<bool> get signedIn => _signedIn;

  /// The API's address, which pages opened in the browser share.
  Uri get apiUrl => Uri.parse(_dio.options.baseUrl);

  /// Picks up the session an earlier launch saved, without a request.
  Future<void> restore() async {
    try {
      _tokens = await _store.readTokens();
    } catch (error) {
      ygLogger('read account session failed (${error.runtimeType})');
      _tokens = null;
    }
    _signedIn.value = _tokens != null;
  }

  /// Keeps the session from a token pair [answer] and runs [prepare] with it;
  /// only then [signedIn] turns true, so «Вход» gives way once it is done.
  Future<R> start<R>(
    Map<String, Object?> answer,
    Future<R> Function() prepare,
  ) async {
    await _keep(_tokenPair(answer));
    final prepared = await prepare();
    _signedIn.value = true;
    return prepared;
  }

  /// Keeps the token pair [answer] in place of the current session, as a
  /// merge of two accounts hands over.
  Future<void> replace(Map<String, Object?> answer) =>
      _keep(_tokenPair(answer));

  /// Refreshes the session ahead of a [AccountAuth.bearerOnce] request. False
  /// once signed out; an outage throws [AccountException].
  Future<bool> refreshNow() async {
    final tokens = _tokens;
    return tokens != null && await _refreshAfter(_header(tokens)) != null;
  }

  /// Signs out here.
  Future<void> end() async {
    _tokens = null;
    try {
      await _store.clearTokens();
    } catch (error) {
      ygLogger('clear account session failed (${error.runtimeType})');
    }
    _signedIn.value = false;
  }

  /// Reads [path] with the session.
  Future<Map<String, Object?>> get(String path) => _send(
    () => _dio.get<Object?>(path, options: _options(AccountAuth.bearer)),
  );

  /// Posts [data] to [path]. A sign-in names its [email] so an unconfirmed
  /// one can continue to the code.
  Future<Map<String, Object?>> post(
    String path, {
    Object? data,
    AccountAuth auth = AccountAuth.none,
    String? email,
  }) => _send(
    () => _dio.post<Object?>(path, data: data, options: _options(auth)),
    email: email,
  );

  static Options? _options(AccountAuth auth) =>
      auth == AccountAuth.none ? null : Options(extra: {_auth: auth});

  /// The JSON object of a successful answer, or the [AccountException] the
  /// failure stands for.
  static Future<Map<String, Object?>> _send(
    Future<Response<Object?>> Function() request, {
    String? email,
  }) async {
    try {
      final data = (await request()).data;
      if (data is Map<String, Object?>) return data;
      throw const AccountException(AccountError.unexpected);
    } on DioException catch (error) {
      throw AccountException.fromDio(error, email: email);
    }
  }

  /// Adds the access token to a bearer request.
  void _authorize(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[_auth] == null) return handler.next(options);
    final tokens = _tokens;
    if (tokens == null) {
      return handler.reject(
        DioException(
          requestOptions: options,
          error: const AccountException(AccountError.signedOut),
        ),
      );
    }
    options.headers['Authorization'] = _header(tokens);
    handler.next(options);
  }

  /// Refreshes the session after a 401 to a [AccountAuth.bearer] request and
  /// repeats it once.
  Future<void> _refreshOnRefusal(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final options = error.requestOptions;
    if (error.response?.statusCode != 401 ||
        options.extra[_auth] != AccountAuth.bearer) {
      return handler.next(error);
    }
    try {
      final tokens = await _refreshAfter(
        options.headers['Authorization'] as String?,
      );
      if (tokens == null) {
        return handler.next(
          error.copyWith(error: const AccountException(AccountError.signedOut)),
        );
      }
      options.extra[_auth] = AccountAuth.bearerOnce;
      handler.resolve(await _dio.fetch<Object?>(options));
    } on AccountException catch (refused) {
      handler.next(error.copyWith(error: refused));
    } on DioException catch (failed) {
      handler.next(failed);
    }
  }

  Future<void> _keep(AccountTokens tokens) async {
    await _store.saveTokens(tokens);
    _tokens = tokens;
  }

  /// The current tokens after [rejected] got a 401: fresh ones from a single
  /// shared refresh, or null once signed out.
  Future<AccountTokens?> _refreshAfter(String? rejected) {
    final current = _tokens;
    if (current == null) return Future.value();
    // Another request already rotated them.
    if (_header(current) != rejected) return Future.value(current);
    return _refreshing ??= _refresh(current)
        .whenComplete(() => _refreshing = null);
  }

  Future<AccountTokens?> _refresh(AccountTokens current) async {
    try {
      final tokens = _tokenPair(
        await post(
          '/api/app/auth/refresh',
          data: {'refreshToken': current.refresh},
        ),
      );
      await _keep(tokens);
      return tokens;
    } on AccountException catch (error) {
      // Only the backend's refusal ends the session; an outage keeps it for
      // the next attempt.
      if (error.error != AccountError.signedOut) rethrow;
      await _onRevoked();
      await end();
      return null;
    }
  }

  static String _header(AccountTokens tokens) => 'Bearer ${tokens.access}';

  static AccountTokens _tokenPair(Map<String, Object?> data) {
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    if (access is! String || refresh is! String) {
      throw const AccountException(AccountError.unexpected);
    }
    return AccountTokens(access: access, refresh: refresh);
  }
}
