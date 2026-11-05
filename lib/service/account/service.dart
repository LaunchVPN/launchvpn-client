import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/account/device_claim.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/session_store.dart';
import 'package:onexray/service/account/telegram_auth.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/settings/language/brand_language.dart';
import 'package:onexray/service/shared/share/service.dart';

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
    void Function(Uri link)? addSubscription,
    String Function()? language,
    TelegramBrowserAuth? telegram,
  }) : telegram = telegram ?? TelegramBrowserAuth(),
       _store = store ?? AccountSessionStore(),
       _language = language ?? (() => BrandLanguage.current.languageCode),
       _readDevice = readDevice ?? AppHostApi().deviceIdentity,
       _removeSubscription =
           removeSubscription ??
           ((url) => SubscriptionLinkService().remove(url)),
       _addSubscription = addSubscription ?? ShareService().addAppLink {
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

  /// Telegram's sign-in in the browser. The deep-link handler hands it the
  /// `launchvpn://auth` returns.
  final TelegramBrowserAuth telegram;
  final AccountSessionStore _store;
  final Future<DeviceIdentity?> Function() _readDevice;
  final Future<void> Function(String url) _removeSubscription;

  /// The queue system links take, so the account's subscription is
  /// confirmed, added and reported as one from a link is.
  final void Function(Uri link) _addSubscription;

  /// The App's language, `ru` or `en`, for the emails the backend sends.
  final String Function() _language;
  final _signedIn = ValueNotifier(false);
  AccountTokens? _tokens;
  Future<AccountTokens?>? _refreshing;
  bool _subscriptionMissing = false;
  bool _unfinishedDeletion = false;

  ValueListenable<bool> get signedIn => _signedIn;

  /// The account had no active subscription when this session last read it,
  /// the trial included. False until read, and after a restart.
  bool get subscriptionMissing => _subscriptionMissing;

  /// The wait before another code when the backend names none.
  static const _resendGap = Duration(seconds: 60);

  /// Picks up the session and the Telegram attempt saved by an earlier
  /// launch, without a request.
  Future<void> restore() async {
    await telegram.restore();
    try {
      _tokens = await _store.readTokens();
    } catch (error) {
      ygLogger('read account session failed (${error.runtimeType})');
      _tokens = null;
    }
    _signedIn.value = _tokens != null;
  }

  /// Signs in by email and adds the account's subscription, unless it has
  /// none or it could not be read. Throws [AccountException] when the
  /// sign-in itself fails; for an unconfirmed email it carries the
  /// [PendingSignup] the backend mailed a code for.
  Future<void> login({required String email, required String password}) async {
    final device = await _device();
    return _signIn(
      await _send(
        () => _dio.post<Object?>(
          '/api/app/auth/login',
          data: {
            'email': email,
            'password': password,
            ...device.toJson(),
            'deviceModel': ?device.model,
          },
        ),
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
    final data = await _send(
      () => _dio.post<Object?>(
        '/api/app/auth/signup',
        data: {
          'email': email,
          'password': password,
          ...device.toJson(),
          'language': _language(),
        },
      ),
    );
    final token = data['signupToken'];
    if (token is! String || token.isEmpty) {
      throw const AccountException(AccountError.unexpected);
    }
    return PendingSignup(
      email: email,
      token: token,
      resendIn: _wait(data),
      trialAvailable: PendingSignup.trialIn(data),
    );
  }

  /// Confirms [signup] with the mailed [code], signs in and adds the
  /// account's subscription as [login] does.
  Future<void> verifyCode(PendingSignup signup, String code) async {
    final device = await _device();
    return _signIn(
      await _send(
        () => _dio.post<Object?>(
          '/api/app/auth/verify-code',
          data: {
            'email': signup.email,
            'code': code,
            'signupToken': signup.token,
            ...device.toJson(),
          },
        ),
      ),
    );
  }

  /// Mails a new code for [signup] and returns the wait before the next.
  Future<Duration> resendCode(PendingSignup signup) async => _wait(
    await _send(
      () => _dio.post<Object?>(
        '/api/app/auth/resend-code',
        data: {'signupToken': signup.token, 'language': _language()},
      ),
    ),
  );

  /// Opens Telegram's sign-in in the browser and completes with its code once
  /// the person is back in the App. The form stays usable meanwhile: they may
  /// come back without finishing. Throws [AccountException].
  Future<TelegramCode> openTelegramLogin() => telegram.authorize(
    TelegramAuthPurpose.login,
    (challenge) => Uri.parse(_dio.options.baseUrl)
        .resolve('/api/auth/telegram/start')
        .replace(
          queryParameters: {
            'mode': 'app_login',
            'lang': _language(),
            'challenge': challenge,
          },
        ),
  );

  /// Signs in with the code from [openTelegramLogin] and adds the account's
  /// subscription as [login] does.
  Future<void> exchangeTelegramLogin(TelegramCode code) async =>
      _signIn(await _exchange(code));

  /// Opens Telegram's page for linking it to the signed-in account and
  /// completes with its code once the person is back. Throws
  /// [AccountException], [AccountError.alreadyLinked] among others.
  Future<TelegramCode> openTelegramLink() =>
      telegram.authorize(TelegramAuthPurpose.link, (challenge) async {
        final data = await _send(
          () => _dio.post<Object?>(
            '/api/app/link/telegram/start',
            data: {'challenge': challenge, 'lang': _language()},
            options: _bearer,
          ),
        );
        final url = switch (data['url']) {
          final String url => Uri.tryParse(url),
          _ => null,
        };
        // Only a web page goes to the browser.
        if (url == null || !(url.isScheme('https') || url.isScheme('http'))) {
          throw const AccountException(AccountError.unexpected);
        }
        return url;
      });

  /// Links Telegram with the code from [openTelegramLink]. The backend merges
  /// the two accounts and answers with the survivor's session, which replaces
  /// this one, and the account's subscription, when it changed, replaces the
  /// previous one on the device.
  /// Throws [AccountException], [AccountError.telegramTaken] when that
  /// Telegram has an account with an email of its own.
  Future<TelegramLink> exchangeTelegramLink(TelegramCode code) async {
    final previous = await _store.readSubscriptionUrl();
    // The trip through the browser may outlast the access token, and a
    // refused exchange burns the code, so it goes out freshly refreshed and
    // without a retry.
    final tokens = _tokens;
    if (tokens == null || await _refreshAfter(_header(tokens)) == null) {
      throw const AccountException(AccountError.signedOut);
    }
    final answer = await _exchange(code, options: _bearerOnce);
    await _keep(_tokenPair(answer));
    final current = await _readSubscription(_subscriptionLink);
    final changed = current != null && current.url != previous;
    if (changed && previous != null) {
      try {
        await _removeSubscription(previous);
      } catch (error) {
        ygLogger('remove account subscription failed (${error.runtimeType})');
      }
    }
    if (changed) addSubscription(current);
    return TelegramLink(
      addedDays: switch (answer['addedDays']) {
        final int days when days > 0 => days,
        _ => 0,
      },
      replacedSubscription: changed,
    );
  }

  /// Keeps the session from a token pair answer, then reads the account's
  /// subscription and adds it once signed in. An account without one claims
  /// the trial, which the backend refuses to one that had it, unless the
  /// answer says the trial already started. Only the code from the email
  /// says so; a login cannot tell an account that never had a subscription
  /// from an ended one.
  Future<void> _signIn(Map<String, Object?> answer) async {
    await _keep(_tokenPair(answer));
    _unfinishedDeletion = false;
    final trialStarted = answer['trialGranted'] == true;
    final link = await _readSubscription(
      () async =>
          await _subscriptionLink() ??
          (trialStarted ? null : await _claimTrial()),
    );
    _signedIn.value = true;
    if (link != null) addSubscription(link);
  }

  /// Signs in, or links Telegram, with the code from the browser.
  Future<Map<String, Object?>> _exchange(
    TelegramCode code, {
    Options? options,
  }) async {
    final device = await _device();
    return _send(
      () => _dio.post<Object?>(
        '/api/app/auth/exchange',
        data: {
          'code': code.code,
          'verifier': code.verifier,
          ...device.toJson(),
        },
        options: options,
      ),
    );
  }

  /// What [read] makes of the account's subscription; null when the backend
  /// could not tell, which only the log keeps.
  static Future<T?> _readSubscription<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on AccountException catch (error) {
      ygLogger('read account subscription failed (${error.error.name})');
      return null;
    }
  }

  Future<SubscriptionDeepLink?> _claimTrial() async {
    final device = await _device();
    try {
      await _send(
        () => _dio.post<Object?>(
          '/api/app/trial',
          data: {'hwid': device.hwid},
          options: _bearer,
        ),
      );
    } on AccountException catch (error) {
      ygLogger('claim trial failed (${error.error.name})');
      return null;
    }
    return _subscriptionLink();
  }

  /// The account's subscription, its link marked as the account's.
  Future<AccountSubscription> accountSubscription() async {
    final data = await _send(
      () => _dio.get<Object?>('/api/subscription', options: _bearer),
    );
    final maxDevices = switch (data['maxDevices']) {
      final int max when max > 0 => max,
      _ => null,
    };
    final configLink = data['configLink'];
    _subscriptionMissing =
        data['active'] != true || configLink is! String || configLink.isEmpty;
    if (configLink is! String || _subscriptionMissing) {
      return AccountSubscription(maxDevices: maxDevices);
    }
    final link = SubscriptionDeepLink.fromUrl(configLink);
    if (link == null) throw const AccountException(AccountError.unexpected);
    await _store.saveSubscriptionUrl(link.url);
    return AccountSubscription(link: link, maxDevices: maxDevices);
  }

  Future<SubscriptionDeepLink?> _subscriptionLink() async =>
      (await accountSubscription()).link;

  /// Sends the account's subscription [link] down the queue system links
  /// take.
  void addSubscription(SubscriptionDeepLink link) => _addSubscription(link.uri);

  /// What the backend knows about the account.
  Future<AccountDetails> details() async => AccountDetails.fromJson(
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
    await _forget();
  }

  /// Deletes the account on the backend, then forgets it here as [logout]
  /// does. Throws [AccountException] and stays signed in when the deletion
  /// did not happen. A session the backend refuses even after a refresh
  /// deletes nothing: it signs out here, throws [AccountError.signedOut] and
  /// leaves [takeUnfinishedDeletion] for «Вход».
  Future<void> deleteAccount() async {
    try {
      await _send(
        () => _dio.post<Object?>(
          '/api/app/account/delete',
          data: const <String, Object?>{},
          options: _bearer,
        ),
      );
    } on AccountException catch (error) {
      if (error.error != AccountError.signedOut) rethrow;
      // Before signing out: «Вход» may open as soon as the session ends.
      _unfinishedDeletion = true;
      await _forget();
      rethrow;
    }
    await _forget();
  }

  /// Whether a deletion found the session gone since the last sign-in, so
  /// the person signs in again to delete the account. Reading clears it.
  bool takeUnfinishedDeletion() {
    final unfinished = _unfinishedDeletion;
    _unfinishedDeletion = false;
    return unfinished;
  }

  /// Removes the subscription the account brought and signs out here.
  Future<void> _forget() async {
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

  /// A bearer request a 401 does not refresh and repeat.
  static final _bearerOnce = Options(
    extra: {_BearerInterceptor.bearer: true, _BearerInterceptor.retried: true},
  );

  Future<DeviceClaim> _device() => DeviceClaim.read(_readDevice);

  Future<void> _keep(AccountTokens tokens) async {
    await _store.saveTokens(tokens);
    _tokens = tokens;
  }

  Future<void> _signOut() async {
    _tokens = null;
    _subscriptionMissing = false;
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

  /// How long the backend asks to wait before another code.
  static Duration _wait(Map<Object?, Object?> data) =>
      switch (data['resendIn'] ?? data['retryAfter']) {
        final int seconds when seconds >= 0 => Duration(seconds: seconds),
        _ => _resendGap,
      };

  /// The JSON object of a successful answer, or the [AccountException] the
  /// failure stands for. A sign-in names its [email] so an unconfirmed one
  /// can continue to the code.
  static Future<Map<String, Object?>> _send(
    Future<Response<Object?>> Function() request, {
    String? email,
  }) async {
    try {
      final data = (await request()).data;
      if (data is Map<String, Object?>) return data;
      throw const AccountException(AccountError.unexpected);
    } on DioException catch (error) {
      throw _failure(error, email: email);
    }
  }

  static AccountException _failure(DioException error, {String? email}) {
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
      retryAfter: data.containsKey('retryAfter') ? _wait(data) : null,
      signup: email != null && token is String && token.isNotEmpty
          ? PendingSignup(
              email: email,
              token: token,
              resendIn: _resendGap,
              trialAvailable: PendingSignup.trialIn(data),
            )
          : null,
    );
  }
}

/// Adds the access token to bearer requests and refreshes it on a 401.
final class _BearerInterceptor extends Interceptor {
  _BearerInterceptor(this._account);

  static const bearer = 'account.bearer';
  static const retried = 'account.retried';

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
        options.extra[retried] == true) {
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
      options.extra[retried] = true;
      handler.resolve(await _account._dio.fetch<Object?>(options));
    } on AccountException catch (error) {
      handler.next(err.copyWith(error: error));
    } on DioException catch (error) {
      handler.next(error);
    }
  }
}
