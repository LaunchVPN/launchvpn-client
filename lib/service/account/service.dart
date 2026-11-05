import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/session_store.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';

/// The person's LaunchVPN account on this device: its session and the
/// requests that carry it.
///
/// Bearer requests that come back 401 refresh the session once, shared by all
/// requests waiting on it, and are retried once. A refused refresh signs out.
/// Tokens, the subscription link and response bodies are never logged.
final class AccountService {
  AccountService({
    required this._dio,
    AccountSessionStore? store,
    Future<DeviceIdentity?> Function()? readDevice,
    Future<void> Function(String url)? removeSubscription,
  }) : _store = store ?? AccountSessionStore(),
       _readDevice = readDevice ?? AppHostApi().deviceIdentity,
       _removeSubscription =
           removeSubscription ??
           ((url) => SubscriptionLinkService().remove(url)) {
    _dio.interceptors.add(_BearerInterceptor(this));
  }

  static final instance = AccountService(
    dio: Dio(
      BaseOptions(
        baseUrl: Brand.apiUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
  );

  final Dio _dio;
  final AccountSessionStore _store;
  final Future<DeviceIdentity?> Function() _readDevice;
  final Future<void> Function(String url) _removeSubscription;
  final _signedIn = ValueNotifier(false);
  AccountTokens? _tokens;
  Future<AccountTokens?>? _refreshing;

  ValueListenable<bool> get signedIn => _signedIn;

  /// Picks up the session saved by an earlier launch, without a request.
  Future<void> restore() async {
    try {
      _tokens = await _store.readTokens();
    } catch (error) {
      ygLogger('read account session failed (${error.runtimeType})');
      _tokens = null;
    }
    _signedIn.value = _tokens != null;
  }

  /// Signs in by email and returns the account's subscription as a
  /// `launchvpn://sub/add` link, or null when it has none or could not be
  /// read. Throws [AccountException] when the sign-in itself fails.
  Future<Uri?> login({required String email, required String password}) async {
    final device = await _device();
    final tokens = _tokenPair(
      await _send(
        () => _dio.post<Object?>(
          '/api/app/auth/login',
          data: {
            'email': email,
            'password': password,
            'hwid': device.hwid,
            'platform': device.os.toLowerCase(),
            if (device.model.isNotEmpty) 'deviceModel': device.model,
          },
        ),
      ),
    );
    await _keep(tokens);
    Uri? link;
    try {
      link = await accountSubscription();
    } on AccountException catch (error) {
      ygLogger('read account subscription failed (${error.error.name})');
    }
    _signedIn.value = true;
    return link;
  }

  /// The account's subscription as a `launchvpn://sub/add` link, marked as
  /// the account's, or null when it has none.
  Future<Uri?> accountSubscription() async {
    final data = await _send(
      () => _dio.get<Object?>('/api/subscription', options: _bearer),
    );
    final configLink = data['configLink'];
    if (data['active'] != true || configLink is! String || configLink.isEmpty) {
      return null;
    }
    final link = SubscriptionDeepLink.fromUrl(configLink);
    if (link == null) throw const AccountException(AccountError.unexpected);
    await _store.saveSubscriptionUrl(link.url);
    return link.uri;
  }

  /// What the backend knows about the account.
  Future<AccountProfile> profile() async => AccountProfile.fromJson(
    await _send(() => _dio.get<Object?>('/api/me', options: _bearer)),
  );

  /// The devices on the account's subscription, this one marked.
  Future<AccountDevices> devices() async {
    final device = await _device();
    return AccountDevices.fromJson(
      await _send(() => _dio.get<Object?>('/api/devices', options: _bearer)),
      currentHwid: device.hwid,
    );
  }

  /// Takes another device off the subscription, which frees its place.
  Future<void> removeDevice(String hwid) => _send(
    () => _dio.post<Object?>(
      '/api/devices/disconnect',
      data: {'hwid': hwid},
      options: _bearer,
    ),
  );

  /// Revokes this device's session and removes the subscription the account
  /// brought, keeping one added from a link. Signs out here even when the
  /// backend cannot be reached.
  Future<void> logout() async {
    try {
      await _send(
        () => _dio.post<Object?>('/api/app/auth/logout', options: _bearer),
      );
    } on AccountException catch (error) {
      ygLogger('revoke account session failed (${error.error.name})');
    }
    try {
      if (await _store.readSubscriptionUrl() case final url?) {
        await _removeSubscription(url);
        await _store.clearSubscriptionUrl();
      }
    } catch (error) {
      ygLogger('remove account subscription failed (${error.runtimeType})');
    }
    await _signOut();
  }

  static final _bearer = Options(extra: {_BearerInterceptor.bearer: true});

  Future<DeviceIdentity> _device() async {
    try {
      final device = await _readDevice();
      if (device != null) return device;
    } catch (error) {
      ygLogger('read device identity failed (${error.runtimeType})');
    }
    throw const AccountException(AccountError.unexpected);
  }

  Future<void> _keep(AccountTokens tokens) async {
    await _store.saveTokens(tokens);
    _tokens = tokens;
  }

  Future<void> _signOut() async {
    _tokens = null;
    try {
      await _store.clearTokens();
    } catch (error) {
      ygLogger('clear account session failed (${error.runtimeType})');
    }
    _signedIn.value = false;
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
        await _send(
          () => _dio.post<Object?>(
            '/api/app/auth/refresh',
            data: {'refreshToken': current.refresh},
          ),
        ),
      );
      await _keep(tokens);
      return tokens;
    } on AccountException catch (error) {
      // Only the backend's refusal ends the session; an outage keeps it for
      // the next attempt.
      if (error.error != AccountError.signedOut) rethrow;
      await _signOut();
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

  /// The JSON object of a successful answer, or the [AccountException] the
  /// failure stands for.
  static Future<Map<String, Object?>> _send(
    Future<Response<Object?>> Function() request,
  ) async {
    try {
      final data = (await request()).data;
      if (data is Map<String, Object?>) return data;
      throw const AccountException(AccountError.unexpected);
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  static AccountException _failure(DioException error) {
    final cause = error.error;
    if (cause is AccountException) return cause;
    final response = error.response;
    if (response == null) {
      return error.type == DioExceptionType.cancel
          ? const AccountException(AccountError.unexpected)
          : const AccountException(AccountError.network);
    }
    final data = response.data;
    return AccountException(
      AccountError.fromCode(data is Map ? data['code'] : null),
    );
  }
}

/// Adds the access token to bearer requests and refreshes it on a 401.
final class _BearerInterceptor extends Interceptor {
  _BearerInterceptor(this._account);

  static const bearer = 'account.bearer';
  static const _retried = 'account.retried';

  final AccountService _account;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[bearer] != true) return handler.next(options);
    final tokens = _account._tokens;
    if (tokens == null) {
      return handler.reject(
        DioException(
          requestOptions: options,
          error: const AccountException(AccountError.signedOut),
        ),
      );
    }
    options.headers['Authorization'] = AccountService._header(tokens);
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 ||
        options.extra[bearer] != true ||
        options.extra[_retried] == true) {
      return handler.next(err);
    }
    try {
      final tokens = await _account._refreshAfter(
        options.headers['Authorization'] as String?,
      );
      if (tokens == null) {
        return handler.next(
          err.copyWith(error: const AccountException(AccountError.signedOut)),
        );
      }
      options.extra[_retried] = true;
      handler.resolve(await _account._dio.fetch<Object?>(options));
    } on AccountException catch (error) {
      handler.next(err.copyWith(error: error));
    } on DioException catch (error) {
      handler.next(error);
    }
  }
}
