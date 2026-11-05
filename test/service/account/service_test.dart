import 'dart:async';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
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

  group('signup', () {
    const signup = PendingSignup(
      email: 'ivan@proton.me',
      token: 'st1',
      resendIn: Duration(seconds: 60),
    );
    const verifyPath = '/api/app/auth/verify-code';

    test('mails a code and keeps the attempt in memory only', () async {
      api.signupWith(token: 'st1', resendIn: 42);
      final service = account();

      final pending = await service.signup(
        email: 'ivan@proton.me',
        password: 'long-secret',
      );

      expect(pending.email, 'ivan@proton.me');
      expect(pending.token, 'st1');
      expect(pending.resendIn, const Duration(seconds: 42));
      expect(api.bodies('/api/app/auth/signup'), [
        {
          'email': 'ivan@proton.me',
          'password': 'long-secret',
          'hwid': 'device-hwid',
          'platform': 'android',
          'language': 'ru',
        },
      ]);
      expect(service.signedIn.value, isFalse);
    });

    test('a registered email is refused', () async {
      api.refuse('/api/app/auth/signup', 409, 'email_taken');

      await expectLater(
        account().signup(email: 'ivan@proton.me', password: 'long-secret'),
        throwsA(_error(AccountError.emailTaken)),
      );
    });

    test(
      'the right code signs in and hands over the trial subscription',
      () async {
        api.verifyWith(access: 'a1', refresh: 'r1');
        api.subscription(_configLink);
        final service = account();

        final link = await service.verifyCode(signup, '123456');

        expect(link, _subscriptionLink);
        expect(service.signedIn.value, isTrue);
        expect(api.bodies(verifyPath), [
          {
            'email': 'ivan@proton.me',
            'code': '123456',
            'signupToken': 'st1',
            'hwid': 'device-hwid',
            'platform': 'android',
          },
        ]);
        expect(api.bodies('/api/app/trial'), isEmpty);
        final restarted = account();
        await restarted.restore();
        expect(restarted.signedIn.value, isTrue);
      },
    );

    test('a wrong code says how many attempts are left', () async {
      api.refuse(verifyPath, 400, 'invalid_code', {'attemptsLeft': 3});

      await expectLater(
        account().verifyCode(signup, '000000'),
        throwsA(
          _error(AccountError.invalidCode)
              .having((e) => e.attemptsLeft, 'attemptsLeft', 3),
        ),
      );
    });

    test('an expired code asks for a new one', () async {
      api.refuse(verifyPath, 410, 'code_expired');
      final service = account();

      await expectLater(
        service.verifyCode(signup, '123456'),
        throwsA(_error(AccountError.codeExpired)),
      );
      expect(service.signedIn.value, isFalse);
    });

    test('resending sends the attempt token and restarts the wait', () async {
      api.resendWith(resendIn: 60);

      expect(await account().resendCode(signup), const Duration(seconds: 60));
      expect(api.bodies('/api/app/auth/resend-code'), [
        {'signupToken': 'st1', 'language': 'ru'},
      ]);
    });

    test('resending too early says how long to wait', () async {
      api.refuse('/api/app/auth/resend-code', 429, 'rate_limited', {
        'retryAfter': 17,
      });

      await expectLater(
        account().resendCode(signup),
        throwsA(
          _error(AccountError.rateLimited).having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 17),
          ),
        ),
      );
    });

    test('an unconfirmed email on login continues to the code', () async {
      api.refuse('/api/app/auth/login', 403, 'email_not_verified', {
        'signupToken': 'st2',
      });

      await expectLater(
        account().login(email: 'ivan@proton.me', password: 'pw'),
        throwsA(
          _error(AccountError.emailNotVerified).having(
            (e) => (e.signup?.email, e.signup?.token),
            'signup',
            ('ivan@proton.me', 'st2'),
          ),
        ),
      );
    });
  });

  group('Telegram', () {
    late FakeBrowser browser;

    setUp(() => browser = FakeBrowser());

    AccountService telegramAccount() =>
        accountServiceFor(api, browser: browser, random: _CountingRandom());

    test('opens the browser with an S256 challenge and redeems the code with '
        'its verifier', () async {
      api.exchangeWith(access: 'a1', refresh: 'r1');
      api.subscription(_configLink);
      final service = telegramAccount();

      final attempt = service.openTelegramLogin();
      await pumpEventQueue();
      // RFC 7636 S256 of the verifier the bytes 0..31 make, by Python.
      expect(browser.opened, [
        Uri.parse(
          'https://api.test/api/auth/telegram/start?mode=app_login&lang=ru'
          '&challenge=6oZqdX5MOLq_qBJ8vppAnT4fk6AP8UiP9zX8-Rev_9A',
        ),
      ]);
      expect(
        service.telegram.handleReturn(Uri.parse('launchvpn://auth?code=c1')),
        isTrue,
      );
      final link = await service.exchangeTelegramLogin(await attempt);

      expect(link, _subscriptionLink);
      expect(service.signedIn.value, isTrue);
      expect(api.bodies('/api/app/auth/exchange'), [
        {
          'code': 'c1',
          'verifier': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
          'hwid': 'device-hwid',
          'platform': 'android',
        },
      ]);
    });

    for (final (error, expected) in [
      ('cancelled', AccountError.cancelled),
      ('telegram_failed', AccountError.telegramFailed),
      ('account_blocked', AccountError.accountBlocked),
      ('not_found', AccountError.unexpected),
    ]) {
      test('a return with error=$error fails as ${expected.name}', () async {
        final service = telegramAccount();
        final attempt = service.openTelegramLogin();
        await pumpEventQueue();

        service.telegram.handleReturn(
          Uri.parse('launchvpn://auth?error=$error'),
        );

        await expectLater(attempt, throwsA(_error(expected)));
        expect(api.requests, isEmpty);
      });
    }

    test('a refused code does not sign in', () async {
      api.refuse('/api/app/auth/exchange', 401, 'invalid_code');
      final service = telegramAccount();
      final attempt = service.openTelegramLogin();
      await pumpEventQueue();
      service.telegram.handleReturn(Uri.parse('launchvpn://auth?code=c1'));

      await expectLater(
        service.exchangeTelegramLogin(await attempt),
        throwsA(_error(AccountError.invalidCode)),
      );
      expect(service.signedIn.value, isFalse);
    });

    test('a device without a browser fails at once', () async {
      browser.available = false;
      final service = telegramAccount();

      await expectLater(
        service.openTelegramLogin(),
        throwsA(_error(AccountError.unexpected)),
      );
      expect(
        service.telegram.handleReturn(Uri.parse('launchvpn://auth?code=c1')),
        isFalse,
      );
    });

    test('returns no attempt waits for are ignored', () async {
      final service = telegramAccount();
      final code = Uri.parse('launchvpn://auth?code=c1');

      expect(service.telegram.handleReturn(code), isFalse);

      final attempt = service.openTelegramLogin();
      await pumpEventQueue();
      expect(
        service.telegram.handleReturn(
          Uri.parse('launchvpn://auth?code=c0&mode=link'),
        ),
        isFalse,
      );
      expect(service.telegram.handleReturn(code), isTrue);
      expect((await attempt).code, 'c1');
      expect(service.telegram.handleReturn(code), isFalse);
    });

    test('a new attempt quietly replaces the waiting one', () async {
      final service = telegramAccount();
      final first = expectLater(
        service.openTelegramLogin(),
        throwsA(_error(AccountError.cancelled)),
      );
      await pumpEventQueue();

      final second = service.openTelegramLogin();
      await pumpEventQueue();
      service.telegram.handleReturn(Uri.parse('launchvpn://auth?code=c2'));

      await first;
      expect((await second).code, 'c2');
      expect(
        browser.opened.map((url) => url.queryParameters['challenge']).toSet(),
        hasLength(2),
      );
    });
  });

  group('trial', () {
    test('an account without a subscription claims the trial once', () async {
      api.loginWith(access: 'a1', refresh: 'r1');
      api.subscription(null);
      api.trialGrants(_configLink);

      final link = await account().login(
        email: 'ivan@proton.me',
        password: 'pw',
      );

      expect(link, _subscriptionLink);
      expect(api.bodies('/api/app/trial'), [
        {'hwid': 'device-hwid'},
      ]);
      expect(api.authorizations('/api/app/trial'), ['Bearer a1']);
    });

    test('a used trial leaves the account without a subscription', () async {
      api.verifyWith(access: 'a1', refresh: 'r1');
      api.subscription(null);
      api.refuse('/api/app/trial', 403, 'trial_used');
      final service = account();

      final link = await service.verifyCode(
        const PendingSignup(
          email: 'ivan@proton.me',
          token: 'st1',
          resendIn: Duration(seconds: 60),
        ),
        '123456',
      );

      expect(link, isNull);
      expect(service.signedIn.value, isTrue);
      expect(service.subscriptionMissing, isTrue);
      expect(api.bodies('/api/app/trial'), hasLength(1));
    });
  });
}

/// Bytes 0, 1, 2… where the App wants randomness, for a known verifier.
final class _CountingRandom implements Random {
  int _next = 0;

  @override
  int nextInt(int max) => _next++ % max;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1000) / 1000;
}

final _subscriptionLink = Uri.parse(
  'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
);

TypeMatcher<AccountException> _error(AccountError error) =>
    isA<AccountException>().having((e) => e.error, 'error', error);

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
