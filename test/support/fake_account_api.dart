import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/account/telegram_auth.dart';

typedef _Reply = Future<(int, Map<String, Object?>)> Function(RequestOptions);

/// The backend's account routes, answered in memory. Records every request so
/// tests can check what the app sent.
final class FakeAccountApi implements HttpClientAdapter {
  /// What each request carried when it was sent. A retry reuses and changes
  /// its [RequestOptions], so they are copied here.
  final requests = <({String path, Object? data, Object? authorization})>[];
  final _rejected = <String>{};
  final _routes = <String, _Reply>{};

  void loginWith({required String access, required String refresh}) =>
      _routes['/api/app/auth/login'] = (_) async => _pair(access, refresh);

  /// The backend's `{"ok": false, "code": …}` answer to a login.
  void refuseLogin(int status, String code) =>
      refuse('/api/app/auth/login', status, code);

  /// The backend's `{"ok": false, "code": …}` answer to [path], with the
  /// [extra] fields some refusals carry.
  void refuse(
    String path,
    int status,
    String code, [
    Map<String, Object?> extra = const {},
  ]) =>
      _routes[path] = (_) async =>
          (status, {'ok': false, 'code': code, ...extra});

  /// Signup mails a code and hands back the token of this attempt.
  void signupWith({required String token, int resendIn = 60}) =>
      _routes['/api/app/auth/signup'] = (_) async =>
          (200, {'ok': true, 'resendIn': resendIn, 'signupToken': token});

  /// The right code: the email is confirmed and the device signed in.
  void verifyWith({required String access, required String refresh}) =>
      _routes['/api/app/auth/verify-code'] = (_) async {
        final (status, pair) = _pair(access, refresh);
        return (status, {...pair, 'trialGranted': true});
      };

  void resendWith({int resendIn = 60}) =>
      _routes['/api/app/auth/resend-code'] = (_) async =>
          (200, {'ok': true, 'resendIn': resendIn});

  /// The trial starts and the account's subscription becomes [configLink].
  void trialGrants(String configLink) => _routes['/api/app/trial'] = (_) async {
    subscription(configLink);
    return (200, <String, Object?>{'ok': true, 'endDate': '2026-11-08'});
  };

  /// The code from a Telegram return signs in with this token pair.
  void exchangeWith({required String access, required String refresh}) =>
      _routes['/api/app/auth/exchange'] = (_) async => _pair(access, refresh);

  /// Bodies sent to [path], in order.
  List<Object?> bodies(String path) => [
    for (final request in requests)
      if (request.path == path) request.data,
  ];

  /// No connection to the backend at all.
  void unreachable() => _routes['/api/app/auth/login'] = (options) async =>
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );

  void refreshWith({
    required String access,
    required String refresh,
    Future<void>? after,
  }) => _routes['/api/app/auth/refresh'] = (_) async {
    await after;
    return _pair(access, refresh);
  };

  void refuseRefresh() =>
      _routes['/api/app/auth/refresh'] = (_) async =>
          (401, {'ok': false, 'code': 'invalid_token'});

  /// The account's subscription, or none when [configLink] is null.
  void subscription(String? configLink) =>
      _routes['/api/subscription'] = (_) async => (
        200,
        configLink == null
            ? {'active': false}
            : {'active': true, 'configLink': configLink},
      );

  void me({required String email, required bool telegramLinked}) =>
      _routes['/api/me'] = (_) async => (
        200,
        {
          'email': email,
          'emailVerified': true,
          'telegramLinked': telegramLinked,
        },
      );

  /// The panel's devices for the account, as `/api/devices` passes them on.
  /// Removing one takes it off the list.
  void devices(List<Map<String, Object?>> devices, {required int max}) {
    final listed = [...devices];
    _routes['/api/devices'] = (_) async =>
        (200, {'devices': listed, 'maxDevices': max});
    _routes['/api/devices/disconnect'] = (options) async {
      final hwid = (options.data as Map)['hwid'];
      listed.removeWhere((device) => device['hwid'] == hwid);
      return (200, <String, Object?>{'ok': true});
    };
  }

  /// The panel fails to remove a device.
  void refuseDeviceRemoval() =>
      _routes['/api/devices/disconnect'] = (_) async =>
          (502, {'ok': false, 'code': 'disconnect_failed'});

  /// Every bearer route answers 401 to [access], as when it expired.
  void rejectAccess(String access) => _rejected.add(access);

  List<Object?> get refreshBodies => bodies('/api/app/auth/refresh');

  List<Object?> authorizations(String path) => [
    for (final request in requests)
      if (request.path == path) request.authorization,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bearer = options.headers['Authorization'];
    requests.add((
      path: options.path,
      data: options.data,
      authorization: bearer,
    ));
    final (
      status,
      body,
    ) = bearer is String && _rejected.contains(bearer.substring(7))
        ? (401, {'ok': false, 'code': 'invalid_token'})
        : await (_routes[options.path] ??
              (_) async => (200, <String, Object?>{'ok': true}))(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  static (int, Map<String, Object?>) _pair(String access, String refresh) => (
    200,
    {
      'ok': true,
      'accessToken': access,
      'refreshToken': refresh,
      'expiresIn': 3600,
    },
  );
}

/// The external browser: records what the App opened in it.
final class FakeBrowser {
  final opened = <Uri>[];

  /// Whether the device has a browser to open a page in.
  bool available = true;

  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return available;
  }
}

/// An [AccountService] that talks to [api] from a Pixel 9, with this device's
/// subscriptions behind [removeSubscription] and Telegram's sign-in opening
/// in [browser].
AccountService accountServiceFor(
  FakeAccountApi api, {
  Future<void> Function(String url)? removeSubscription,
  FakeBrowser? browser,
  Random? random,
}) => AccountService(
  dio: Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = api,
  removeSubscription: removeSubscription ?? (_) async {},
  language: () => 'ru',
  telegram: TelegramBrowserAuth(
    openBrowser: (browser ?? FakeBrowser()).open,
    random: random,
  ),
  readDevice: () async => DeviceIdentity(
    hwid: 'device-hwid',
    os: 'Android',
    osVersion: '16',
    model: 'Pixel 9',
  ),
);
