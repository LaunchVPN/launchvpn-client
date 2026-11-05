import 'package:onexray/service/account/account_data.dart';
import 'package:onexray/service/account/device_claim.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/session.dart';
import 'package:onexray/service/account/telegram_auth.dart';

/// Signing in with Telegram, and linking it to the signed-in account. Both
/// go through Telegram's page in the browser and exchange the code it
/// returns.
final class TelegramAccount {
  TelegramAccount({
    required this.browser,
    required this._session,
    required this._data,
    required this._device,
    required this._language,
  });

  /// Telegram's page in the browser. The deep-link handler hands it the
  /// `launchvpn://auth` returns.
  final TelegramBrowserAuth browser;
  final AccountSession _session;

  /// Finishes a sign-in, and a link, with the account's subscription.
  final AccountData _data;
  final Future<DeviceClaim> Function() _device;

  /// The App's language, `ru` or `en`, for Telegram's page.
  final String Function() _language;

  /// Opens Telegram's sign-in in the browser and completes with its code once
  /// the person is back in the App. The form stays usable meanwhile: they may
  /// come back without finishing. Throws [AccountException].
  Future<TelegramCode> openLogin() => browser.authorize(
    TelegramAuthPurpose.login,
    (challenge) => _session.apiUrl
        .resolve('/api/auth/telegram/start')
        .replace(
          queryParameters: {
            'mode': 'app_login',
            'lang': _language(),
            'challenge': challenge,
          },
        ),
  );

  /// Signs in with the code from [openLogin] and adds the account's
  /// subscription as an email sign-in does.
  Future<void> exchangeLogin(TelegramCode code) async =>
      _data.signIn(await _exchange(code));

  /// Opens Telegram's page for linking it to the signed-in account and
  /// completes with its code once the person is back. Throws
  /// [AccountException], [AccountError.alreadyLinked] among others.
  Future<TelegramCode> openLink() =>
      browser.authorize(TelegramAuthPurpose.link, (challenge) async {
        final data = await _session.post(
          '/api/app/link/telegram/start',
          data: {'challenge': challenge, 'lang': _language()},
          auth: AccountAuth.bearer,
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

  /// Links Telegram with the code from [openLink]. The backend merges the two
  /// accounts and answers with the survivor's session, which replaces this
  /// one, and the account's subscription, when it changed, replaces the
  /// previous one on the device. Throws [AccountException],
  /// [AccountError.telegramTaken] when that Telegram has an account with an
  /// email of its own.
  Future<TelegramLink> exchangeLink(TelegramCode code) async {
    final previous = await _data.savedSubscriptionUrl();
    // The trip through the browser may outlast the access token, and a
    // refused exchange burns the code, so it goes out freshly refreshed and
    // without a retry.
    if (!await _session.refreshNow()) {
      throw const AccountException(AccountError.signedOut);
    }
    final answer = await _exchange(code, auth: AccountAuth.bearerOnce);
    await _session.replace(answer);
    return TelegramLink(
      addedDays: switch (answer['addedDays']) {
        final int days when days > 0 => days,
        _ => 0,
      },
      replacedSubscription: await _data.replaceAfterMerge(previous),
    );
  }

  /// Signs in, or links Telegram, with the code from the browser.
  Future<Map<String, Object?>> _exchange(
    TelegramCode code, {
    AccountAuth auth = AccountAuth.none,
  }) async {
    final device = await _device();
    return _session.post(
      '/api/app/auth/exchange',
      data: {'code': code.code, 'verifier': code.verifier, ...device.toJson()},
      auth: auth,
    );
  }
}
