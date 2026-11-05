/// A signup waiting for the code from the email. Its [token] proves this
/// attempt to the backend; it lives in memory only, for this one flow.
final class PendingSignup {
  const PendingSignup({
    required this.email,
    required this.token,
    required this.resendIn,
  });

  final String email;
  final String token;

  /// How long until another code may be sent.
  final Duration resendIn;
}

/// What `GET /api/me` says about the signed-in account.
final class AccountProfile {
  const AccountProfile({required this.email, required this.telegramLinked});

  /// Null for an account that has only Telegram.
  final String? email;
  final bool telegramLinked;

  static AccountProfile fromJson(Map<String, Object?> data) => AccountProfile(
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
