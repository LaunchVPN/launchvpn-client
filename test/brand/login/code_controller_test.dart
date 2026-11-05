// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/brand/login/code_controller.dart';
import 'package:onexray/service/account/model.dart';

import '../../support/fake_account_api.dart';

const _configLink = 'https://sub.launch.tel/abc';
const _verifyPath = '/api/app/auth/verify-code';
const _resendPath = '/api/app/auth/resend-code';

void main() {
  late FakeAccountApi api;
  late List<Uri> opened;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = FakeAccountApi();
    opened = [];
  });

  /// The code step for a signup mailed 42 seconds' wait ago.
  EmailCodeController codeStep() => EmailCodeController(
    account: accountServiceFor(api, addSubscription: opened.add),
    signup: const PendingSignup(
      email: 'ivan@proton.me',
      token: 'st1',
      resendIn: Duration(seconds: 42),
    ),
  );

  test('resend waits out the countdown, then restarts it', () {
    fakeAsync((time) {
      api.resendWith(resendIn: 60);
      final code = codeStep();
      expect(code.state.resendIn, const Duration(seconds: 42));

      time.elapse(const Duration(seconds: 2));
      expect(code.state.resendIn, const Duration(seconds: 40));
      code.resend();
      time.elapse(const Duration(milliseconds: 100));
      expect(api.bodies(_resendPath), isEmpty);

      time.elapse(const Duration(seconds: 40));
      expect(code.state.canResend, isTrue);
      code.resend();
      time.elapse(const Duration(milliseconds: 100));

      expect(api.bodies(_resendPath), hasLength(1));
      expect(code.state.resendIn, const Duration(seconds: 60));
      code.close();
    });
  });

  test('a resend refused as too early waits as long as the backend says', () {
    fakeAsync((time) {
      api.refuse(_resendPath, 429, 'rate_limited', {'retryAfter': 17});
      final code = codeStep();
      time.elapse(const Duration(seconds: 42));

      code.resend();
      time.elapse(const Duration(milliseconds: 100));

      expect(code.state.resendIn, const Duration(seconds: 17));
      expect(code.state.error, isNull);
      code.close();
    });
  });

  test('a resend for a gone attempt asks to start over', () {
    fakeAsync((time) {
      api.refuse(_resendPath, 410, 'code_expired');
      final code = codeStep();
      time.elapse(const Duration(seconds: 42));

      code.resend();
      time.elapse(const Duration(milliseconds: 100));

      expect(code.state.error, EmailCodeError.attemptGone);
      code.close();
    });
  });

  test('a wrong code says how many attempts are left', () async {
    api.refuse(_verifyPath, 400, 'invalid_code', {'attemptsLeft': 2});
    final code = codeStep();
    addTearDown(code.close);

    await code.verify('000000');

    expect(code.state.error, EmailCodeError.wrongCode);
    expect(code.state.attemptsLeft, 2);
    expect(opened, isEmpty);
  });

  test('an expired or burned code asks for a new one', () async {
    final code = codeStep();
    addTearDown(code.close);

    api.refuse(_verifyPath, 410, 'code_expired');
    await code.verify('123456');
    expect(code.state.error, EmailCodeError.codeExpired);

    api.refuse(_verifyPath, 400, 'invalid_code', {'attemptsLeft': 0});
    await code.verify('000000');
    expect(code.state.error, EmailCodeError.codeExpired);
  });

  test('a blocked account or a closed app sign-in says why', () async {
    final code = codeStep();
    addTearDown(code.close);

    api.refuse(_verifyPath, 403, 'account_blocked');
    await code.verify('123456');
    expect(code.state.error, EmailCodeError.accountBlocked);

    api.refuse(_verifyPath, 403, 'app_not_available');
    await code.verify('123456');
    expect(code.state.error, EmailCodeError.appNotAvailable);
  });

  test('the right code adds the account subscription', () async {
    api.verifyWith(access: 'a1', refresh: 'r1');
    api.subscription(_configLink);
    final code = codeStep();
    addTearDown(code.close);

    await code.verify(' 123456 ');

    expect(code.state.error, isNull);
    expect(api.bodies(_verifyPath).single, containsPair('code', '123456'));
    expect(opened, [
      Uri.parse(
        'launchvpn://sub/add?url=${Uri.encodeQueryComponent(_configLink)}',
      ),
    ]);
  });
}
