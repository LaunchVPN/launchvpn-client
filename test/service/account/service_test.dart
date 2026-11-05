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
  late List<Uri> added;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = FakeAccountApi();
    added = [];
  });

  AccountService account() =>
      accountServiceFor(api, addSubscription: added.add);

  test(
    'login keeps the session and hands over the subscription link',
    () async {
      api.loginWith(access: 'a1', refresh: 'r1');
      api.subscription(_configLink);
      final service = account();

      await service.email.login(email: 'ivan@proton.me', password: 'pw');

      expect(service.session.signedIn.value, isTrue);
      expect(added, [
        Uri.parse(
          'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
        ),
      ]);
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
      expect(restarted.session.signedIn.value, isTrue);
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

      expect((await service.data.subscription()).link, isNotNull);

      expect(api.refreshBodies, [
        {'refreshToken': 'r1'},
      ]);
      expect(api.authorizations('/api/subscription'), [
        'Bearer a1',
        'Bearer a2',
      ]);
      expect(service.session.signedIn.value, isTrue);
    },
  );

  group('the backend ending the session', () {
    late List<String> removed;

    /// Signed in with tokens `a1`/`r1` and the account's subscription kept,
    /// then the access token expires.
    Future<AccountService> expired() async {
      removed = [];
      api.loginWith(access: 'a1', refresh: 'r1');
      api.subscription(_configLink);
      final service = accountServiceFor(
        api,
        addSubscription: added.add,
        removeSubscription: (url) async => removed.add(url),
      );
      await service.email.login(email: 'ivan@proton.me', password: 'pw');
      api.rejectAccess('a1');
      return service;
    }

    test('a refused refresh signs out as «Выйти» does and says the session '
        'ended', () async {
      final service = await expired();
      api.refuseRefresh();

      await expectLater(
        service.data.subscription(),
        throwsA(_error(AccountError.signedOut)),
      );

      expect(service.session.signedIn.value, isFalse);
      expect(removed, [_configLink]);
      expect(service.data.takeForcedSignOut(), ForcedSignOut.sessionEnded);
      expect(service.data.takeForcedSignOut(), isNull);
      final restarted = account();
      await restarted.restore();
      expect(restarted.session.signedIn.value, isFalse);
    });

    test(
      'a refused refresh while signing in leaves the device signed out',
      () async {
        api.loginWith(access: 'a1', refresh: 'r1');
        api.subscription(_configLink);
        api.rejectAccess('a1');
        api.refuseRefresh();
        final service = account();

        await expectLater(
          service.email.login(email: 'ivan@proton.me', password: 'pw'),
          throwsA(_error(AccountError.signedOut)),
        );

        expect(service.session.signedIn.value, isFalse);
        expect(added, isEmpty);
        // «Вход» said it with the failure; the next one says nothing.
        expect(service.data.takeForcedSignOut(), isNull);
      },
    );

    for (final (name, fail) in [
      (
        'no connection',
        (FakeAccountApi api) => api.unreachable('/api/app/auth/refresh'),
      ),
      (
        'a server error',
        (FakeAccountApi api) =>
            api.refuse('/api/app/auth/refresh', 502, 'bad_gateway'),
      ),
    ]) {
      test('$name on refresh keeps the session', () async {
        final service = await expired();
        fail(api);

        await expectLater(service.data.subscription(), throwsA(anything));

        expect(service.session.signedIn.value, isTrue);
        expect(removed, isEmpty);
        expect(service.data.takeForcedSignOut(), isNull);
      });
    }
  });

  test('requests rejected together share one refresh', () async {
    await signIn(api, account);
    api.rejectAccess('a1');
    final refresh = Completer<void>();
    api.refreshWith(access: 'a2', refresh: 'r2', after: refresh.future);
    api.subscription(_configLink);
    final service = account();
    await service.restore();

    final first = service.data.subscription();
    final second = service.data.subscription();
    await pumpEventQueue();
    refresh.complete();

    expect(await Future.wait([first, second]), everyElement(isNotNull));
    expect(api.refreshBodies, hasLength(1));
  });

  test('a subscription that failed to leave with logout leaves at the next '
      'launch', () async {
    api.loginWith(access: 'a1', refresh: 'r1');
    api.subscription(_configLink);
    final removed = <String>[];
    var failing = true;
    AccountService device() => accountServiceFor(
      api,
      removeSubscription: (url) async {
        if (failing) throw StateError('tunnel busy');
        removed.add(url);
      },
    );
    final service = device();
    await service.email.login(email: 'ivan@proton.me', password: 'pw');

    await service.data.logout();
    expect(service.session.signedIn.value, isFalse);
    failing = false;
    final restarted = device();
    await restarted.restore();

    expect(removed, [_configLink]);
    expect(await restarted.data.savedSubscriptionUrl(), isNull);
  });

  test('logout revokes the session on the server and here', () async {
    await signIn(api, account);
    final service = account();
    await service.restore();

    await service.data.logout();

    expect(api.authorizations('/api/app/auth/logout'), ['Bearer a1']);
    expect(service.session.signedIn.value, isFalse);
    final restarted = account();
    await restarted.restore();
    expect(restarted.session.signedIn.value, isFalse);
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
        addSubscription: added.add,
        removeSubscription: (url) async => removed.add(url),
      );
      await service.email.login(email: 'ivan@proton.me', password: 'pw');
      api.requests.clear();
      return service;
    }

    Future<void> expectSignedOut(AccountService service) async {
      expect(service.session.signedIn.value, isFalse);
      expect(removed, [_configLink]);
      final restarted = account();
      await restarted.restore();
      expect(restarted.session.signedIn.value, isFalse);
    }

    test('deletes the account on the server, then forgets it here', () async {
      final service = await signedIn();

      await service.data.deleteAccount();

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
        service.data.deleteAccount(),
        throwsA(_error(AccountError.signedOut)),
      );

      await expectSignedOut(service);
      expect(
        service.data.takeForcedSignOut(),
        ForcedSignOut.deletionUnfinished,
      );
      expect(service.data.takeForcedSignOut(), isNull);
    });

    test(
      'signing in again drops the request to sign in for deletion',
      () async {
        final service = await signedIn();
        api.rejectAccess('a1');
        api.refuseRefresh();
        await expectLater(service.data.deleteAccount(), throwsA(anything));
        api.loginWith(access: 'a2', refresh: 'r2');

        await service.email.login(email: 'ivan@proton.me', password: 'pw');

        expect(service.data.takeForcedSignOut(), isNull);
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

        await expectLater(
          service.data.deleteAccount(),
          throwsA(_error(expected)),
        );

        expect(service.session.signedIn.value, isTrue);
        expect(removed, isEmpty);
        await service.data.details();
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

      final pending = await service.email.signup(
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
      expect(service.session.signedIn.value, isFalse);
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

        final created = await service.email.signup(
          email: 'ivan@proton.me',
          password: 'long-secret',
        );
        final unconfirmed = await service.email
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
        account().email.signup(
          email: 'ivan@proton.me',
          password: 'long-secret',
        ),
        throwsA(_error(AccountError.emailTaken)),
      );
    });

    test(
      'the right code signs in and hands over the trial subscription',
      () async {
        api.verifyWith(access: 'a1', refresh: 'r1');
        api.subscription(_configLink);
        final service = account();

        await service.email.verifyCode(signup, '123456');

        expect(added, [_subscriptionLink]);
        expect(service.session.signedIn.value, isTrue);
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
        expect(restarted.session.signedIn.value, isTrue);
      },
    );

    test('a wrong code says how many attempts are left', () async {
      api.refuse(verifyPath, 400, 'invalid_code', {'attemptsLeft': 3});

      await expectLater(
        account().email.verifyCode(signup, '000000'),
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
        service.email.verifyCode(signup, '123456'),
        throwsA(_error(AccountError.codeExpired)),
      );
      expect(service.session.signedIn.value, isFalse);
    });

    test('resending sends the attempt token and restarts the wait', () async {
      api.resendWith(resendIn: 60);

      expect(
        await account().email.resendCode(signup),
        const Duration(seconds: 60),
      );
      expect(api.bodies('/api/app/auth/resend-code'), [
        {'signupToken': 'st1', 'language': 'ru'},
      ]);
    });

    test('resending too early says how long to wait', () async {
      api.refuse('/api/app/auth/resend-code', 429, 'rate_limited', {
        'retryAfter': 17,
      });

      await expectLater(
        account().email.resendCode(signup),
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
        account().email.login(email: 'ivan@proton.me', password: 'pw'),
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

    AccountService telegramAccount() => accountServiceFor(
      api,
      addSubscription: added.add,
      browser: browser,
      random: _CountingRandom(),
    );

    test('opens the browser with an S256 challenge and redeems the code with '
        'its verifier', () async {
      api.exchangeWith(access: 'a1', refresh: 'r1');
      api.subscription(_configLink);
      final service = telegramAccount();

      final attempt = service.telegram.openLogin();
      await pumpEventQueue();
      // RFC 7636 S256 of the verifier the bytes 0..31 make, by Python.
      expect(browser.opened, [
        Uri.parse(
          'https://api.test/api/auth/telegram/start?mode=app_login&lang=ru'
          '&challenge=6oZqdX5MOLq_qBJ8vppAnT4fk6AP8UiP9zX8-Rev_9A',
        ),
      ]);
      expect(
        service.telegram.browser.handleReturn(
          Uri.parse('launchvpn://auth?code=c1'),
        ),
        isTrue,
      );
      await service.telegram.exchangeLogin(await attempt);

      expect(added, [_subscriptionLink]);
      expect(service.session.signedIn.value, isTrue);
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
        final attempt = service.telegram.openLogin();
        await pumpEventQueue();

        service.telegram.browser.handleReturn(
          Uri.parse('launchvpn://auth?error=$error'),
        );

        await expectLater(attempt, throwsA(_error(expected)));
        expect(api.requests, isEmpty);
      });
    }

    test('a refused code does not sign in', () async {
      api.refuse('/api/app/auth/exchange', 401, 'invalid_code');
      final service = telegramAccount();
      final attempt = service.telegram.openLogin();
      await pumpEventQueue();
      service.telegram.browser.handleReturn(
        Uri.parse('launchvpn://auth?code=c1'),
      );

      await expectLater(
        service.telegram.exchangeLogin(await attempt),
        throwsA(_error(AccountError.invalidCode)),
      );
      expect(service.session.signedIn.value, isFalse);
    });

    test('a device without a browser fails at once', () async {
      browser.available = false;
      final service = telegramAccount();

      await expectLater(
        service.telegram.openLogin(),
        throwsA(_error(AccountError.unexpected)),
      );
      expect(
        service.telegram.browser.handleReturn(
          Uri.parse('launchvpn://auth?code=c1'),
        ),
        isFalse,
      );
    });

    test('returns no attempt waits for are ignored', () async {
      final service = telegramAccount();
      final code = Uri.parse('launchvpn://auth?code=c1');

      expect(service.telegram.browser.handleReturn(code), isFalse);

      final attempt = service.telegram.openLogin();
      await pumpEventQueue();
      expect(
        service.telegram.browser.handleReturn(
          Uri.parse('launchvpn://auth?code=c0&mode=link'),
        ),
        isFalse,
      );
      expect(service.telegram.browser.handleReturn(code), isTrue);
      expect((await attempt).code, 'c1');
      expect(service.telegram.browser.handleReturn(code), isFalse);
    });

    group('after the App was closed', () {
      var now = DateTime(2026, 11, 5, 12);

      AccountService restartedAfter(Duration away) {
        final returned = now.add(away);
        return accountServiceFor(
          api,
          addSubscription: added.add,
          browser: browser,
          now: () => returned,
        );
      }

      setUp(() => now = DateTime(2026, 11, 5, 12));

      /// Opens Telegram's sign-in, which the system closes with the App.
      Future<void> leaveForTelegram() async {
        final first = accountServiceFor(
          api,
          addSubscription: added.add,
          browser: browser,
          random: _CountingRandom(),
          now: () => now,
        );
        unawaited(first.telegram.openLogin());
        await pumpEventQueue();
      }

      test('an attempt younger than ten minutes completes with its '
          'verifier', () async {
        api.exchangeWith(access: 'a1', refresh: 'r1');
        api.subscription(_configLink);
        await leaveForTelegram();
        final service = restartedAfter(const Duration(minutes: 9));
        await service.restore();

        final code = service.telegram.browser.resume(TelegramAuthPurpose.login);
        expect(
          service.telegram.browser.resume(TelegramAuthPurpose.link),
          isNull,
        );
        expect(
          service.telegram.browser.handleReturn(
            Uri.parse('launchvpn://auth?code=c1'),
          ),
          isTrue,
        );
        await service.telegram.exchangeLogin(await code!);
        expect(added, hasLength(1));

        expect(api.bodies('/api/app/auth/exchange').single, {
          'code': 'c1',
          'verifier': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
          'hwid': 'device-hwid',
          'platform': 'android',
        });
        // Claimed once.
        expect(
          service.telegram.browser.resume(TelegramAuthPurpose.login),
          isNull,
        );
      });

      test('an older attempt is forgotten', () async {
        await leaveForTelegram();
        final service = restartedAfter(const Duration(minutes: 11));
        await service.restore();

        expect(
          service.telegram.browser.resume(TelegramAuthPurpose.login),
          isNull,
        );
        expect(
          service.telegram.browser.handleReturn(
            Uri.parse('launchvpn://auth?code=c1'),
          ),
          isFalse,
        );
      });

      test('a finished attempt is not restored', () async {
        final first = accountServiceFor(
          api,
          addSubscription: added.add,
          browser: browser,
          now: () => now,
        );
        final attempt = first.telegram.openLogin();
        await pumpEventQueue();
        first.telegram.browser.handleReturn(
          Uri.parse('launchvpn://auth?code=c1'),
        );
        await attempt;
        await pumpEventQueue();

        final service = restartedAfter(const Duration(minutes: 1));
        await service.restore();

        expect(
          service.telegram.browser.resume(TelegramAuthPurpose.login),
          isNull,
        );
      });
    });

    test('a new attempt quietly replaces the waiting one', () async {
      final service = telegramAccount();
      final first = expectLater(
        service.telegram.openLogin(),
        throwsA(_error(AccountError.cancelled)),
      );
      await pumpEventQueue();

      final second = service.telegram.openLogin();
      await pumpEventQueue();
      service.telegram.browser.handleReturn(
        Uri.parse('launchvpn://auth?code=c2'),
      );

      await first;
      expect((await second).code, 'c2');
      expect(
        browser.opened.map((url) => url.queryParameters['challenge']).toSet(),
        hasLength(2),
      );
    });

    test('an attempt replaced before its page is ready opens and keeps '
        'nothing', () async {
      final auth = TelegramBrowserAuth(
        openBrowser: browser.open,
        random: _CountingRandom(),
      );
      final firstPage = Completer<Uri>();
      final first = expectLater(
        auth.authorize(TelegramAuthPurpose.link, (_) => firstPage.future),
        throwsA(_error(AccountError.cancelled)),
      );
      final second = auth.authorize(
        TelegramAuthPurpose.login,
        (_) => Uri.parse('https://api.test/second'),
      );
      await pumpEventQueue();

      firstPage.complete(Uri.parse('https://api.test/first'));
      await first;

      expect(browser.opened, [Uri.parse('https://api.test/second')]);
      final restarted = TelegramBrowserAuth(openBrowser: browser.open);
      await restarted.restore();
      expect(restarted.resume(TelegramAuthPurpose.login), isNotNull);
      second.ignore();
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
        addSubscription: added.add,
        browser: browser,
        random: _CountingRandom(),
        removeSubscription: (url) async => removed.add(url),
      );
      await service.email.login(email: 'ivan@proton.me', password: 'pw');
      api.requests.clear();
      api.linkStartWith(startUrl);
      api.refreshWith(access: 'a2', refresh: 'r2');
      api.exchangeWith(access: 'a3', refresh: 'r3', addedDays: 30);
      api.subscription(telegramLink);
      return service;
    }

    /// Starts linking and comes back from the browser with [ret].
    Future<TelegramCode> linkAndReturn(AccountService service, String ret) {
      final attempt = service.telegram.openLink();
      return pumpEventQueue().then((_) {
        service.telegram.browser.handleReturn(Uri.parse(ret));
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
      final linked = await service.telegram.exchangeLink(code);

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
      expect(linked.replacedSubscription, isTrue);
      expect(
        added.last,
        Uri.parse(
          'launchvpn://sub/add?url=${Uri.encodeQueryComponent(telegramLink)}',
        ),
      );
      expect(removed, [_configLink]);
      expect(api.authorizations('/api/subscription'), ['Bearer a3']);

      final restarted = account();
      await restarted.restore();
      await restarted.data.details();
      expect(api.authorizations('/api/me'), ['Bearer a3']);
    });

    test('a subscription that stays is left on the device', () async {
      final service = await signedIn();
      api.exchangeWith(access: 'a3', refresh: 'r3');
      api.subscription(_configLink);

      final linked = await service.telegram.exchangeLink(
        await linkAndReturn(service, 'launchvpn://auth?code=c1&mode=link'),
      );

      expect(linked.addedDays, 0);
      expect(linked.replacedSubscription, isFalse);
      expect(removed, isEmpty);
    });

    test('a merge whose subscription read failed is finished by the next '
        'read', () async {
      final service = await signedIn();
      api.refuse('/api/subscription', 502, 'bad_gateway');

      final linked = await service.telegram.exchangeLink(
        await linkAndReturn(service, 'launchvpn://auth?code=c1&mode=link'),
      );
      expect(linked.replacedSubscription, isFalse);
      expect(removed, isEmpty);

      api.subscription(telegramLink);
      await service.data.subscription();

      expect(removed, [_configLink]);
      expect(await service.data.savedSubscriptionUrl(), telegramLink);
    });

    test('a Telegram with its own email account is refused and nothing '
        'changes', () async {
      final service = await signedIn();
      api.refuse('/api/app/auth/exchange', 409, 'telegram_taken');

      await expectLater(
        service.telegram.exchangeLink(
          await linkAndReturn(service, 'launchvpn://auth?code=c1&mode=link'),
        ),
        throwsA(_error(AccountError.telegramTaken)),
      );

      expect(removed, isEmpty);
      expect(service.session.signedIn.value, isTrue);
      expect(api.bodies('/api/app/auth/exchange'), hasLength(1));
      await service.data.details();
      expect(api.authorizations('/api/me'), ['Bearer a2']);
    });

    test(
      'an account that has Telegram already never opens the browser',
      () async {
        final service = await signedIn();
        api.refuse('/api/app/link/telegram/start', 409, 'already_linked');

        await expectLater(
          service.telegram.openLink(),
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

      await account().email.login(email: 'ivan@proton.me', password: 'pw');

      expect(added, [_subscriptionLink]);
      expect(api.bodies('/api/app/trial'), [
        {'hwid': 'device-hwid'},
      ]);
      expect(api.authorizations('/api/app/trial'), ['Bearer a1']);
    });

    const signup = PendingSignup(
      email: 'ivan@proton.me',
      token: 'st1',
      resendIn: Duration(seconds: 60),
    );

    test('a confirmed email whose trial started does not claim it', () async {
      api.verifyWith(access: 'a1', refresh: 'r1');
      api.subscription(null);
      api.trialGrants(_configLink);

      await account().email.verifyCode(signup, '123456');
      expect(added, isEmpty);
      expect(api.bodies('/api/app/trial'), isEmpty);
    });

    for (final granted in [false, null]) {
      test(
        'a confirmed email with trialGranted $granted claims the trial',
        () async {
          api.verifyWith(access: 'a1', refresh: 'r1', trialGranted: granted);
          api.subscription(null);
          api.trialGrants(_configLink);

          await account().email.verifyCode(signup, '123456');
          expect(added, [_subscriptionLink]);
          expect(api.bodies('/api/app/trial'), hasLength(1));
        },
      );
    }

    test(
      'a confirmed email the signup offered no trial does not claim it',
      () async {
        api.verifyWith(access: 'a1', refresh: 'r1', trialGranted: false);
        api.subscription(null);
        api.trialGrants(_configLink);
        final service = account();

        await service.email.verifyCode(
          const PendingSignup(
            email: 'ivan@proton.me',
            token: 'st1',
            resendIn: Duration(seconds: 60),
            trialAvailable: false,
          ),
          '123456',
        );

        expect(api.bodies('/api/app/trial'), isEmpty);
        expect(added, isEmpty);
        expect(service.session.signedIn.value, isTrue);
        expect(service.data.subscriptionMissing, isTrue);
      },
    );

    test('a used trial leaves the account without a subscription', () async {
      api.verifyWith(access: 'a1', refresh: 'r1', trialGranted: false);
      api.subscription(null);
      api.refuse('/api/app/trial', 403, 'trial_used');
      final service = account();

      await service.email.verifyCode(signup, '123456');

      expect(added, isEmpty);
      expect(service.session.signedIn.value, isTrue);
      expect(service.data.subscriptionMissing, isTrue);
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
  await account().email.login(email: 'ivan@proton.me', password: 'pw');
  api.requests.clear();
}
