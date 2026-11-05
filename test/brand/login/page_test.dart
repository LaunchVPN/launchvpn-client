import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/app.dart';
import 'package:onexray/brand/router.dart';
import 'package:onexray/brand/shader_backdrop.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/shared/share/service.dart';

import '../../support/fake_account_api.dart';

const _configLink = 'https://sub.launch.tel/abc';

void main() {
  late FakeAccountApi api;
  late AccountService account;
  late StreamController<bool> subscriptions;
  late List<Uri> opened;
  late FakeBrowser browser;
  late StreamController<Uri> links;
  late ShareService share;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = FakeAccountApi();
    browser = FakeBrowser();
    account = accountServiceFor(
      api,
      browser: browser,
      addSubscription: (link) => share.addAppLink(link),
    );
    opened = [];
  });

  /// The app on a Russian phone with a Pixel's screen and reduced motion,
  /// with [hasSubscription] as the first word of the subscription table.
  Future<void> pumpApp(
    WidgetTester tester, {
    required bool hasSubscription,
  }) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    links = StreamController<Uri>.broadcast(sync: true);
    share = ShareService.forTesting(
      appLinks: links.stream,
      receiveWidgetUri: (_) => false,
    );
    subscriptions = StreamController<bool>();
    addTearDown(() async {
      share.dispose();
      await links.close();
      await subscriptions.close();
    });
    final router = createBrandRouter(
      home: const Text('home-body'),
      settings: const Text('settings-body'),
      account: account,
      watchSubscription: () => subscriptions.stream,
      shareService: share,
      initializeServices: (_) => share.init(),
      openLink: (_, uri) async => opened.add(uri),
    );
    addTearDown(router.dispose);
    tester.platformDispatcher
      ..localeTestValue = const Locale('ru')
      ..localesTestValue = const [Locale('ru')]
      // A still backdrop, so the screens can settle.
      ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    subscriptions.add(hasSubscription);
    await tester.pumpWidget(BrandApp(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'ivan@proton.me',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Пароль'), 'secret');
    await tester.pump();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Войти'));
    await tester.pumpAndSettle();
    await fillForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pumpAndSettle();
  }

  Future<void> createAccount(WidgetTester tester) async {
    await fillForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Создать аккаунт'));
    await tester.pumpAndSettle();
  }

  group('gate', () {
    testWidgets('without a session or a subscription the app opens on «Вход»', (
      tester,
    ) async {
      await pumpApp(tester, hasSubscription: false);

      expect(find.text('Интернет\nбез границ'), findsOneWidget);
      expect(
        find.text(
          'Создайте аккаунт и получите 3 дня бесплатно. Карта не нужна.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Создать аккаунт'),
        findsOneWidget,
      );
      expect(find.text('Уже есть аккаунт?'), findsOneWidget);
      expect(find.text('У меня есть ссылка подписки'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ShaderBackdrop), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Войти'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Войти'), findsOneWidget);
      expect(find.text('Нет аккаунта?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Создать'), findsOneWidget);
    });

    testWidgets('a subscription from a link opens the tabs', (tester) async {
      await pumpApp(tester, hasSubscription: true);

      expect(find.text('home-body'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.text('Войти'), findsNothing);
    });

    testWidgets('a saved session opens the tabs', (tester) async {
      api.loginWith(access: 'a1', refresh: 'r1');
      api.subscription(null);
      await tester.runAsync(
        () => account.email.login(email: 'ivan@proton.me', password: 'pw'),
      );

      await pumpApp(tester, hasSubscription: false);

      expect(find.text('home-body'), findsOneWidget);
    });

    testWidgets('a session the backend ended opens «Вход» to sign in again', (
      tester,
    ) async {
      api.loginWith(access: 'a1', refresh: 'r1');
      api.subscription(null);
      await tester.runAsync(
        () => account.email.login(email: 'ivan@proton.me', password: 'pw'),
      );
      await pumpApp(tester, hasSubscription: false);
      api.rejectAccess('a1');
      api.refuseRefresh();

      await tester.runAsync(
        () => account.data.subscription().then((_) {}, onError: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Сессия завершена. Войдите снова'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Войти'), findsOneWidget);
      expect(find.text('home-body'), findsNothing);
    });
  });

  group('login', () {
    testWidgets(
      'signing in passes the gate and adds the account subscription',
      (tester) async {
        api.loginWith(access: 'a1', refresh: 'r1');
        api.subscription(_configLink);
        await pumpApp(tester, hasSubscription: false);

        await signIn(tester);

        expect(find.text('home-body'), findsOneWidget);
        expect(opened, [
          Uri.parse(
            'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
          ),
        ]);
      },
    );

    for (final (refuse, message) in [
      (
        (FakeAccountApi api) => api.refuseLogin(401, 'invalid_credentials'),
        'Неверная почта или пароль',
      ),
      (
        (FakeAccountApi api) => api.refuseLogin(429, 'rate_limited'),
        'Слишком много попыток. Подождите немного',
      ),
      (
        (FakeAccountApi api) => api.unreachable(),
        'Нет связи с сервером. Попробуйте ещё раз',
      ),
      (
        (FakeAccountApi api) => api.refuseLogin(403, 'account_blocked'),
        'Аккаунт заблокирован. Напишите в поддержку',
      ),
      (
        (FakeAccountApi api) => api.refuseLogin(403, 'app_not_available'),
        'Вход в приложении пока недоступен',
      ),
      // Without the attempt the code screen needs.
      (
        (FakeAccountApi api) => api.refuseLogin(403, 'email_not_verified'),
        'Почта не подтверждена. Попробуйте войти ещё раз',
      ),
    ]) {
      testWidgets('a refused login says «$message»', (tester) async {
        refuse(api);
        await pumpApp(tester, hasSubscription: false);

        await signIn(tester);

        expect(find.text(message), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(opened, isEmpty);
      });
    }

    testWidgets('an unconfirmed email continues to the code', (tester) async {
      api.refuse('/api/app/auth/login', 403, 'email_not_verified', {
        'signupToken': 'st2',
      });
      await pumpApp(tester, hasSubscription: false);

      await signIn(tester);

      expect(find.text('Проверьте\nпочту'), findsOneWidget);
      expect(find.textContaining('ivan@proton.me'), findsOneWidget);
    });

    testWidgets('«У меня есть ссылка подписки» opens a pasted link', (
      tester,
    ) async {
      await pumpApp(tester, hasSubscription: false);

      await tester.tap(find.text('У меня есть ссылка подписки'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, _configLink);
      await tester.tap(find.text('Добавить'));
      await tester.pumpAndSettle();

      expect(opened, [
        Uri.parse(
          'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
        ),
      ]);
    });

    testWidgets('a pasted text that is no link says so as an error', (
      tester,
    ) async {
      await pumpApp(tester, hasSubscription: false);

      await tester.tap(find.text('У меня есть ссылка подписки'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'привет');
      await tester.tap(find.text('Добавить'));
      await tester.pump();

      expect(find.text('Эта ссылка не подходит для LaunchVPN'), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
      expect(opened, isEmpty);
    });
  });

  group('Telegram', () {
    Future<void> returnFromTelegram(WidgetTester tester, String query) async {
      await tester.tap(find.text('Войти через Telegram'));
      await tester.pumpAndSettle();
      expect(browser.opened, hasLength(1));
      links.add(Uri.parse('launchvpn://auth?$query'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'signing in passes the gate and adds the account subscription',
      (tester) async {
        api.exchangeWith(access: 'a1', refresh: 'r1');
        api.subscription(_configLink);
        await pumpApp(tester, hasSubscription: false);

        expect(find.text('или'), findsOneWidget);
        await returnFromTelegram(tester, 'code=c1');

        expect(find.text('home-body'), findsOneWidget);
        expect(opened, [
          Uri.parse(
            'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
          ),
        ]);
      },
    );

    testWidgets('a return after signing in by email meanwhile switches no '
        'account', (tester) async {
      api.loginWith(access: 'a1', refresh: 'r1');
      api.exchangeWith(access: 't1', refresh: 'tr1');
      api.subscription(_configLink);
      await pumpApp(tester, hasSubscription: false);
      await tester.tap(find.text('Войти через Telegram'));
      await tester.pumpAndSettle();

      await signIn(tester);
      links.add(Uri.parse('launchvpn://auth?code=c1'));
      await tester.pumpAndSettle();

      expect(find.text('home-body'), findsOneWidget);
      expect(api.bodies('/api/app/auth/exchange'), isEmpty);
    });

    group('after the system closed the App in the browser', () {
      /// The App left for Telegram's sign-in and was closed meanwhile; this
      /// launch restored what it saved.
      /// In the test's zone: a restored attempt completes in the zone it was
      /// restored in.
      Future<void> restartedDuringSignIn(WidgetTester tester) async {
        unawaited(
          accountServiceFor(
            api,
            browser: browser,
            addSubscription: (link) => share.addAppLink(link),
          ).telegram.openLogin(),
        );
        await tester.pump();
        account = accountServiceFor(
          api,
          browser: browser,
          addSubscription: (link) => share.addAppLink(link),
        );
        await account.restore();
      }

      for (final hasSubscription in [false, true]) {
        testWidgets('the return signs in and adds the account subscription '
            '(subscription from a link: $hasSubscription)', (tester) async {
          api.exchangeWith(access: 'a1', refresh: 'r1');
          api.subscription(_configLink);
          await restartedDuringSignIn(tester);
          await pumpApp(tester, hasSubscription: hasSubscription);

          links.add(Uri.parse('launchvpn://auth?code=c1'));
          await tester.pumpAndSettle();

          expect(account.session.signedIn.value, isTrue);
          expect(find.text('home-body'), findsOneWidget);
          expect(find.text('Интернет\nбез границ'), findsNothing);
          expect(opened, [
            Uri.parse(
              'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
            ),
          ]);
        });
      }

      testWidgets('a failed return says so on «Вход»', (tester) async {
        await restartedDuringSignIn(tester);
        await pumpApp(tester, hasSubscription: false);

        links.add(Uri.parse('launchvpn://auth?error=telegram_failed'));
        await tester.pumpAndSettle();

        expect(
          find.text('Не получилось войти через Telegram. Попробуйте ещё раз'),
          findsOneWidget,
        );
      });
    });

    testWidgets('a failed sign-in asks to try again', (tester) async {
      await pumpApp(tester, hasSubscription: false);

      await returnFromTelegram(tester, 'error=telegram_failed');

      expect(
        find.text('Не получилось войти через Telegram. Попробуйте ещё раз'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
    });

    for (final (error, message) in [
      ('account_blocked', 'Аккаунт заблокирован. Напишите в поддержку'),
      ('app_not_available', 'Вход в приложении пока недоступен'),
    ]) {
      testWidgets('a return with error=$error says «$message»', (tester) async {
        await pumpApp(tester, hasSubscription: false);

        await returnFromTelegram(tester, 'error=$error');

        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('Telegram. Попробуйте'), findsNothing);
      });
    }

    testWidgets('a cancelled sign-in leaves the form as it was', (
      tester,
    ) async {
      await pumpApp(tester, hasSubscription: false);

      await returnFromTelegram(tester, 'error=cancelled');

      expect(find.textContaining('Telegram. Попробуйте'), findsNothing);
      expect(find.text('Войти через Telegram'), findsOneWidget);
    });

    testWidgets('iOS offers no Telegram sign-in', (tester) async {
      await pumpApp(tester, hasSubscription: false);

      expect(find.text('Войти через Telegram'), findsNothing);
      expect(find.text('или'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Создать аккаунт'),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('create account', () {
    Future<void> enterCode(WidgetTester tester, String code) async {
      await tester.enterText(
        find.widgetWithText(TextField, 'Код из 6 цифр'),
        code,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the code from the email passes the gate with the trial', (
      tester,
    ) async {
      api.signupWith(token: 'st1', resendIn: 42);
      api.verifyWith(access: 'a1', refresh: 'r1');
      api.subscription(_configLink);
      await pumpApp(tester, hasSubscription: false);

      await createAccount(tester);

      expect(find.text('Проверьте\nпочту'), findsOneWidget);
      expect(find.byType(ShaderBackdrop), findsOneWidget);
      expect(
        find.text(
          'Отправили код на ivan@proton.me. Введите его, и 3 дня бесплатно '
          'начнутся сразу.',
        ),
        findsOneWidget,
      );
      expect(find.text('Отправить код ещё раз · 0:42'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Отправить код ещё раз · 0:41'), findsOneWidget);

      await enterCode(tester, '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить'));
      await tester.pumpAndSettle();

      expect(find.text('home-body'), findsOneWidget);
      expect(opened, [
        Uri.parse(
          'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
        ),
      ]);
    });

    testWidgets('without a trial to start, the code only confirms the email', (
      tester,
    ) async {
      api.signupWith(token: 'st1', trialAvailable: false);
      await pumpApp(tester, hasSubscription: false);

      await createAccount(tester);

      expect(
        find.text(
          'Отправили код на ivan@proton.me. Введите его, чтобы подтвердить '
          'почту.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a wrong code is explained under the field', (tester) async {
      api.signupWith(token: 'st1');
      api.refuse('/api/app/auth/verify-code', 400, 'invalid_code', {
        'attemptsLeft': 4,
      });
      await pumpApp(tester, hasSubscription: false);
      await createAccount(tester);

      await enterCode(tester, '000000');
      await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить'));
      await tester.pumpAndSettle();

      expect(find.text('Неверный код. Осталось попыток: 4'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('«Изменить» returns to the form with the email kept', (
      tester,
    ) async {
      api.signupWith(token: 'st1');
      await pumpApp(tester, hasSubscription: false);
      await createAccount(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Изменить'));
      await tester.pumpAndSettle();

      expect(find.text('Проверьте\nпочту'), findsNothing);
      expect(find.widgetWithText(TextField, 'ivan@proton.me'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Создать аккаунт'),
        findsOneWidget,
      );
    });

    testWidgets('a registered email is refused on the form', (tester) async {
      api.refuse('/api/app/auth/signup', 409, 'email_taken');
      await pumpApp(tester, hasSubscription: false);

      await createAccount(tester);

      expect(
        find.text('Эта почта уже зарегистрирована. Войдите в аккаунт'),
        findsOneWidget,
      );
    });
  });
}
