import 'package:onexray/service/servers/subscription/deep_link.dart';

/// A signup waiting for the code from the email. Its [token] proves this
/// attempt to the backend; it lives in memory only, for this one flow.
final class PendingSignup {
  const PendingSignup({
    required this.email,
    required this.token,
    required this.resendIn,
    this.trialAvailable = true,
  });

  final String email;
  final String token;

  /// How long until another code may be sent.
  final Duration resendIn;

  /// Whether confirming the email starts the trial. A backend that does not
  /// say is taken to offer it.
  final bool trialAvailable;

  /// The answer to a signup, or to a login of an unconfirmed email, carries
  /// whether the trial waits.
  static bool trialIn(Map<Object?, Object?> data) =>
      data['trialAvailable'] != false;

  /// The wait before another code when the backend names none.
  static const resendGap = Duration(seconds: 60);

  /// How long the backend asks to wait before another code.
  static Duration waitIn(Map<Object?, Object?> data) =>
      switch (data['resendIn'] ?? data['retryAfter']) {
        final int seconds when seconds >= 0 => Duration(seconds: seconds),
        _ => resendGap,
      };
}

/// Why the device signed out without the person asking, for «Вход» to say.
enum ForcedSignOut {
  /// The backend refused the refresh: the session was revoked or expired.
  sessionEnded,

  /// «Удалить аккаунт» found the session gone, so nothing was deleted.
  deletionUnfinished,
}

/// Telegram linked to the signed-in account, which may now be another one:
/// the merge keeps the Telegram side's.
final class TelegramLink {
  const TelegramLink({
    required this.addedDays,
    required this.replacedSubscription,
  });

  /// What the Telegram side's subscription added; 0 when it had none.
  final int addedDays;

  /// The account's subscription changed: the previous one left the device
  /// and the new one went to the link queue. False when it stayed, and when
  /// the account has none.
  final bool replacedSubscription;
}

/// What `GET /api/subscription` says about the account's subscription.
final class AccountSubscription {
  const AccountSubscription({this.link, this.maxDevices});

  /// The subscription to add, marked as the account's; null while the
  /// account has no active one.
  final SubscriptionDeepLink? link;

  /// The devices the panel allows this user. Null when it does not say.
  final int? maxDevices;
}

/// What `GET /api/me` says about the signed-in account.
final class AccountDetails {
  const AccountDetails({required this.email, required this.telegramLinked});

  /// Null for an account that has only Telegram.
  final String? email;
  final bool telegramLinked;

  static AccountDetails fromJson(Map<String, Object?> data) => AccountDetails(
    email: switch (data['email']) {
      final String email when email.isNotEmpty => email,
      _ => null,
    },
    telegramLinked: data['telegramLinked'] == true,
  );
}

/// A device the panel registered on the account's subscription.
final class AccountDevice {
  const AccountDevice({
    required this.hwid,
    required this.current,
    this.model,
    this.platform,
    this.osVersion,
    this.lastSeen,
  });

  final String hwid;

  /// The device this App runs on, which cannot be removed from here.
  final bool current;
  final String? model;
  final String? platform;
  final String? osVersion;

  /// When the device last loaded the subscription.
  final DateTime? lastSeen;

  /// A panel device as `GET /api/devices` lists it. Null without a HWID.
  static AccountDevice? fromJson(Object? data, {required String currentHwid}) {
    if (data is! Map) return null;
    final hwid = data['hwid'];
    if (hwid is! String || hwid.isEmpty) return null;
    String? text(String key) => switch (data[key]) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };
    final seen = text('updatedAt') ?? text('createdAt');
    return AccountDevice(
      hwid: hwid,
      current: hwid == currentHwid,
      model: text('deviceModel'),
      platform: text('platform'),
      osVersion: text('osVersion'),
      lastSeen: seen == null ? null : DateTime.tryParse(seen),
    );
  }
}

/// The devices on the account's subscription and how many it allows.
final class AccountDevices {
  const AccountDevices({required this.items, this.max});

  /// This device first, then the most recently seen.
  final List<AccountDevice> items;

  /// Null when the backend sets no limit.
  final int? max;

  AccountDevices without(String hwid) => AccountDevices(
    items: [
      for (final device in items)
        if (device.hwid != hwid) device,
    ],
    max: max,
  );

  static AccountDevices fromJson(
    Map<String, Object?> data, {
    required String currentHwid,
  }) {
    final listed = data['devices'];
    final items = [
      if (listed is List)
        for (final item in listed)
          ?AccountDevice.fromJson(item, currentHwid: currentHwid),
    ];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    items.sort(
      (a, b) => a.current != b.current
          ? (a.current ? -1 : 1)
          : (b.lastSeen ?? epoch).compareTo(a.lastSeen ?? epoch),
    );
    return AccountDevices(
      items: List.unmodifiable(items),
      max: switch (data['maxDevices']) {
        final int max when max > 0 => max,
        _ => null,
      },
    );
  }
}
