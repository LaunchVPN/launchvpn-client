import 'package:dio/dio.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/account/account_data.dart';
import 'package:onexray/service/account/device_claim.dart';
import 'package:onexray/service/account/email_auth.dart';
import 'package:onexray/service/account/session.dart';
import 'package:onexray/service/account/session_store.dart';
import 'package:onexray/service/account/telegram_account.dart';
import 'package:onexray/service/account/telegram_auth.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/settings/language/brand_language.dart';
import 'package:onexray/service/shared/share/service.dart';

/// The person's LaunchVPN account on this device, wired from its parts:
/// the [session] every request carries, sign-in by [email] or [telegram],
/// and the account's [data]. Callers use the part they need.
final class AccountService {
  factory AccountService({
    required Dio dio,
    AccountSessionStore? store,
    Future<DeviceIdentity?> Function()? readDevice,
    Future<void> Function(String url)? removeSubscription,
    void Function(Uri link)? addSubscription,
    String Function()? language,
    TelegramBrowserAuth? browser,
  }) {
    final keep = store ?? AccountSessionStore();
    late final AccountData data;
    final session = AccountSession(
      dio: dio,
      store: keep,
      onRevoked: () => data.revoked(),
    );
    final read = readDevice ?? AppHostApi().deviceIdentity;
    Future<DeviceClaim> device() => DeviceClaim.read(read);
    final languageCode = language ?? (() => BrandLanguage.current.languageCode);
    data = AccountData(
      session: session,
      store: keep,
      device: device,
      addSubscription: addSubscription ?? ShareService().addAppLink,
      removeSubscription:
          removeSubscription ??
          ((url) => SubscriptionLinkService().remove(url)),
    );
    return AccountService._(
      session: session,
      data: data,
      email: EmailAuth(
        session: session,
        data: data,
        device: device,
        language: languageCode,
      ),
      telegram: TelegramAccount(
        browser: browser ?? TelegramBrowserAuth(),
        session: session,
        data: data,
        device: device,
        language: languageCode,
      ),
    );
  }

  AccountService._({
    required this.session,
    required this.data,
    required this.email,
    required this.telegram,
  });

  static final instance = AccountService(
    dio: Dio(
      BaseOptions(
        baseUrl: Brand.apiUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
  );

  final AccountSession session;
  final AccountData data;
  final EmailAuth email;
  final TelegramAccount telegram;

  /// Picks up the Telegram attempt and the session saved by an earlier
  /// launch, without a request.
  Future<void> restore() async {
    await telegram.browser.restore();
    await session.restore();
  }
}
