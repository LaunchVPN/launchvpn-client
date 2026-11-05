import 'dart:async';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/account/telegram_auth.dart';

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

  group('account deletion', () {
    late List<String> removed;

    /// Signed in with tokens `a1`/`r1` and the account's subscription kept.
    Future<AccountService> signedIn() async {
      removed = [];
      api.loginWith(access: 'a1', refresh: 'r1');
      api.subscription(_configLink);
      final service = accountServiceFor(
        api,
        removeSubscription: (url) async => removed.add(url),
      );
      await service.login(email: 'ivan@proton.me', password: 'pw');
      api.requests.clear();
      return service;
    }

    Future<void> expectSignedOut(AccountService service) async {
      expect(service.signedIn.value, isFalse);
      expect(removed, [_configLink]);
      final restarted = account();
      await restarted.restore();
      expect(restarted.signedIn.value, isFalse);
    }

    test('deletes the account on the server, then forgets it here', () async {
      final service = await signedIn();

      await service.deleteAccount();

      expect(api.bodies('/api/app/account/delete'), [<String, Object?>{}]);
      expect(api.authorizations('/api/app/account/delete'), ['Bearer a1']);
      await expectSignedOut(service);
    });

    test('a session already gone deletes nothing, signs out here and asks to '
        'sign in again', () async {
      final service = await signedIn();
      api.rejectAccess('a1');
      api.refuseRefresh();

      await expectLater(
        service.deleteAccount(),
        throwsA(_error(AccountError.signedOut)),
      );

      await expectSignedOut(service);
      expect(service.takeUnfinishedDeletion(), isTrue);
      expect(service.takeUnfinishedDeletion(), isFalse);
    });

    test(
      'signing in again drops the request to sign in for deletion',
      () async {
        final service = await signedIn();
        api.rejectAccess('a1');
        api.refuseRefresh();
        await expectLater(service.deleteAccount(), throwsA(anything));

        await service.login(email: 'ivan@proton.me', password: 'pw');

        expect(service.takeUnfinishedDeletion(), isFalse);
      },
    );

    for (final (name, fail, expected) in [
      (
        'the panel failing',
        (FakeAccountApi api) =>
            api.refuse('/api/app/account/delete', 502, 'panel_failed'),
        AccountError.unexpected,
      ),
      (
        'no connection',
        (FakeAccountApi api) => api.unreachable('/api/app/account/delete'),
        AccountError.network,
      ),
    ]) {
      test('$name keeps the account and the session', () async {
        final service = await signedIn();
        fail(api);

        await expectLater(service.deleteAccount(), throwsA(_error(expected)));

        expect(service.signedIn.value, isTrue);
        expect(removed, isEmpty);
        await service.profile();
        expect(api.authorizations('/api/me'), ['Bearer a1']);
      });
    }
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

    for (final (answer, expected) in [
      (false, false),
      (true, true),
      (null, true),
    ]) {
      test('trialAvailable $answer from the backend says whether the code '
          'starts the trial', () async {
        api.signupWith(token: 'st1', trialAvailable: answer);
        api.refuse('/api/app/auth/login', 403, 'email_not_verified', {
          'signupToken': 'st2',
          'trialAvailable': ?answer,
        });
        final service = account();

        final created = await service.signup(
          email: 'ivan@proton.me',
          password: 'long-secret',
        );
        final unconfirmed = await service
            .login(email: 'ivan@proton.me', password: 'pw')
            .then<PendingSignup?>(
              (_) => null,
              onError: (Object error) => (error as AccountException).signup,
            );

        expect(created.trialAvailable, expected);
        expect(unconfirmed?.trialAvailable, expected);
      });
    }

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

  group('Telegram link', () {
    const startUrl =
        'https://app.test/api/auth/telegram/start?mode=app_link&ticket=t1';
    const telegramLink = 'https://sub.launch.tel/telegram';
    late FakeBrowser browser;
    late List<String> removed;

    setUp(() {
      browser = FakeBrowser();
      removed = [];
    });

    /// Signed in with tokens `a1`/`r1` and the account's subscription kept
    /// as [_configLink]; Telegram's side brings [telegramLink].
    Future<AccountService> signedIn() async {
      api.loginWith(access: 'a1', refresh: 'r1');
      api.subscription(_configLink);
      final service = accountServiceFor(
        api,
        browser: browser,
        random: _CountingRandom(),
        removeSubscription: (url) async => removed.add(url),
      );
      await service.login(email: 'ivan@proton.me', password: 'pw');
      api.requests.clear();
      api.linkStartWith(startUrl);
      api.refreshWith(access: 'a2', refresh: 'r2');
      api.exchangeWith(access: 'a3', refresh: 'r3', addedDays: 30);
      api.subscription(telegramLink);
      return service;
    }

    /// Starts linking and comes back from the browser with [ret].
    Future<TelegramCode> linkAndReturn(AccountService service, String ret) {
      final attempt = service.openTelegramLink();
      return pumpEventQueue().then((_) {
        service.telegram.handleReturn(Uri.parse(ret));
        return attempt;
      });
    }

    test('starts with the challenge, then merges with the verifier and the '
        'session, and swaps the tokens and the subscription', () async {
      final service = await signedIn();

      final code = await linkAndReturn(
        service,
        'launchvpn://auth?code=c1&mode=link',
      );
      final linked = await service.exchangeTelegramLink(code);

      expect(browser.opened, [Uri.parse(startUrl)]);
      expect(api.bodies('/api/app/link/telegram/start'), [
        {
          'challenge': '6oZqdX5MOLq_qBJ8vppAnT4fk6AP8UiP9zX8-Rev_9A',
          'lang': 'ru',
        },
      ]);
      expect(api.authorizations('/api/app/link/telegram/start'), ['Bearer a1']);
      expect(api.bodies('/api/app/auth/exchange'), [
        {
          'code': 'c1',
          'verifier': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
          'hwid': 'device-hwid',
          'platform': 'android',
        },
      ]);
      // Refreshed first: the trip through the browser may outlast the
      // access token, and a refused exchange burns the code.
      expect(api.authorizations('/api/app/auth/exchange'), ['Bearer a2']);
      expect(linked.addedDays, 30);
      expect(
        linked.subscription,
        Uri.parse(
          'launchvpn://sub/add?url=${Uri.encodeQueryComponent(telegramLink)}',
        ),
      );
      expect(removed, [_configLink]);
      expect(api.authorizations('/api/subscription'), ['Bearer a3']);

      final restarted = account();
      await restarted.restore();
      await restarted.profile();
      expect(api.authorizations('/api/me'), ['Bearer a3']);
    });

    test('a subscription that stays is left on the device', () async {
      final service = await signedIn();
      api.exchangeWith(access: 'a3', refresh: 'r3');
      api.subscription(_configLink);

      final linked = await service.exchangeTelegramLink(
        await linkAndReturn(service, 'launchvpn://auth?code=c1&mode=link'),
      );

      expect(linked.addedDays, 0);
      expect(linked.subscription, isNull);
      expect(removed, isEmpty);
    });

    test('a Telegram with its own email account is refused and nothing '
        'changes', () async {
      final service = await signedIn();
      api.refuse('/api/app/auth/exchange', 409, 'telegram_taken');

      await expectLater(
        service.exchangeTelegramLink(
          await linkAndReturn(service, 'launchvpn://auth?code=c1&mode=link'),
        ),
        throwsA(_error(AccountError.telegramTaken)),
      );

      expect(removed, isEmpty);
      expect(service.signedIn.value, isTrue);
      expect(api.bodies('/api/app/auth/exchange'), hasLength(1));
      await service.profile();
      expect(api.authorizations('/api/me'), ['Bearer a2']);
    });

    test(
      'an account that has Telegram already never opens the browser',
      () async {
        final service = await signedIn();
        api.refuse('/api/app/link/telegram/start', 409, 'already_linked');

        await expectLater(
          service.openTelegramLink(),
          throwsA(_error(AccountError.alreadyLinked)),
        );
        expect(browser.opened, isEmpty);
      },
    );

    test('a cancelled return exchanges nothing', () async {
      final service = await signedIn();

      await expectLater(
        linkAndReturn(service, 'launchvpn://auth?error=cancelled&mode=link'),
        throwsA(_error(AccountError.cancelled)),
      );
      expect(api.bodies('/api/app/auth/exchange'), isEmpty);
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
