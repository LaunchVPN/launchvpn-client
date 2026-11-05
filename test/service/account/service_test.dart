import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/service.dart';

import '../../support/fake_account_api.dart';

const _configLink = 'https://sub.launch.tel/abc';

void main() {
  late FakeAccountApi api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = FakeAccountApi();
  });

  AccountService account() => accountServiceFor(api);

  test(
    'login keeps the session and hands over the subscription link',
    () async {
      api.loginWith(access: 'a1', refresh: 'r1');
      api.subscription(_configLink);
      final service = account();

      final link = await service.login(email: 'ivan@proton.me', password: 'pw');

      expect(service.signedIn.value, isTrue);
      expect(
        link,
        Uri.parse(
          'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
        ),
      );
      expect(api.requests.first.data, {
        'email': 'ivan@proton.me',
        'password': 'pw',
        'hwid': 'device-hwid',
        'platform': 'android',
        'deviceModel': 'Pixel 9',
      });
      expect(api.authorizations('/api/subscription'), ['Bearer a1']);

      final restarted = account();
      await restarted.restore();
      expect(restarted.signedIn.value, isTrue);
    },
  );

  test(
    'a rejected access token is refreshed once and the request retried',
    () async {
      await signIn(api, account);
      api.rejectAccess('a1');
      api.refreshWith(access: 'a2', refresh: 'r2');
      api.subscription(_configLink);
      final service = account();
      await service.restore();

      expect(await service.accountSubscription(), isNotNull);

      expect(api.refreshBodies, [
        {'refreshToken': 'r1'},
      ]);
      expect(api.authorizations('/api/subscription'), [
        'Bearer a1',
        'Bearer a2',
      ]);
      expect(service.signedIn.value, isTrue);
    },
  );

  test('a refused refresh signs out on this device', () async {
    await signIn(api, account);
    api.rejectAccess('a1');
    api.refuseRefresh();
    final service = account();
    await service.restore();

    await expectLater(
      service.accountSubscription(),
      throwsA(
        isA<AccountException>().having(
          (e) => e.error,
          'error',
          AccountError.signedOut,
        ),
      ),
    );

    expect(service.signedIn.value, isFalse);
    final restarted = account();
    await restarted.restore();
    expect(restarted.signedIn.value, isFalse);
  });

  test('requests rejected together share one refresh', () async {
    await signIn(api, account);
    api.rejectAccess('a1');
    final refresh = Completer<void>();
    api.refreshWith(access: 'a2', refresh: 'r2', after: refresh.future);
    api.subscription(_configLink);
    final service = account();
    await service.restore();

    final first = service.accountSubscription();
    final second = service.accountSubscription();
    await pumpEventQueue();
    refresh.complete();

    expect(await Future.wait([first, second]), everyElement(isNotNull));
    expect(api.refreshBodies, hasLength(1));
  });

  test('logout revokes the session on the server and here', () async {
    await signIn(api, account);
    final service = account();
    await service.restore();

    await service.logout();

    expect(api.authorizations('/api/app/auth/logout'), ['Bearer a1']);
    expect(service.signedIn.value, isFalse);
    final restarted = account();
    await restarted.restore();
    expect(restarted.signedIn.value, isFalse);
  });
}

/// Leaves a stored session with tokens `a1`/`r1`, then forgets the requests.
Future<void> signIn(
  FakeAccountApi api,
  AccountService Function() account,
) async {
  api.loginWith(access: 'a1', refresh: 'r1');
  api.subscription(null);
  await account().login(email: 'ivan@proton.me', password: 'pw');
  api.requests.clear();
}
