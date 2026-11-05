import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/app.dart';
import 'package:onexray/brand/router.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/shared/share/service.dart';

import '../../support/fake_account_api.dart';

const _configLink = 'https://sub.launch.tel/abc';

void main() {
  late FakeAccountApi api;
  late AccountService account;
  late StreamController<bool> subscriptions;
  late List<Uri> opened;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = FakeAccountApi();
    account = accountServiceFor(api);
    opened = [];
  });

  /// The app on a Russian phone, with [hasSubscription] as the first word of
  /// the subscription table.
  Future<void> pumpApp(
    WidgetTester tester, {
    required bool hasSubscription,
  }) async {
    final links = StreamController<Uri>.broadcast(sync: true);
    final share = ShareService.forTesting(
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
      ..localesTestValue = const [Locale('ru')];
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
        () => account.login(email: 'ivan@proton.me', password: 'pw'),
      );

      await pumpApp(tester, hasSubscription: false);

      expect(find.text('home-body'), findsOneWidget);
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
      await tester.enterText(find.byType(TextField).last, _configLink);
      await tester.tap(find.text('Добавить'));
      await tester.pumpAndSettle();

      expect(opened, [
        Uri.parse(
          'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
        ),
      ]);
    });
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
