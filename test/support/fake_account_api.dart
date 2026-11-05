import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/account/service.dart';

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
      _routes['/api/app/auth/login'] = (_) async =>
          (status, {'ok': false, 'code': code});

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

  /// Every bearer route answers 401 to [access], as when it expired.
  void rejectAccess(String access) => _rejected.add(access);

  List<Object?> get refreshBodies => [
    for (final request in requests)
      if (request.path == '/api/app/auth/refresh') request.data,
  ];

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

/// An [AccountService] that talks to [api] from a Pixel 9.
AccountService accountServiceFor(FakeAccountApi api) => AccountService(
  dio: Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = api,
  readDevice: () async => DeviceIdentity(
    hwid: 'device-hwid',
    os: 'Android',
    osVersion: '16',
    model: 'Pixel 9',
  ),
);
