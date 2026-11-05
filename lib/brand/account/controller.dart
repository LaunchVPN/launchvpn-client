import 'dart:async';

import 'package:collection/collection.dart';
import 'package:onexray/brand/home/controller.dart' show SubscriptionRefresh;
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';

final class AccountState {
  const AccountState({
    this.signedIn = false,
    this.subscription,
    this.profile,
    this.devices,
    this.inactive = false,
    this.refreshing = false,
    this.linkingTelegram = false,
  });

  final bool signedIn;

  /// The subscription on this device, the account's or one from a link.
  final SubscriptionData? subscription;

  /// Null until loaded, and from a link only.
  final AccountProfile? profile;

  /// Null until loaded, and from a link only.
  final AccountDevices? devices;

  /// The account has no active subscription.
  final bool inactive;

  /// [AccountController.refresh] is running.
  final bool refreshing;

  /// Back from Telegram, the App is linking it with the code it brought.
  final bool linkingTelegram;

  /// Days and traffic as the panel last reported them.
  SubscriptionUserInfo? get usage => switch (subscription) {
    final row? => SubscriptionUserInfo.fromSubscription(row),
    null => null,
  };

  AccountState copyWith({
    bool? signedIn,
    SubscriptionData? Function()? subscription,
    AccountProfile? profile,
    AccountDevices? devices,
    bool? inactive,
    bool? refreshing,
    bool? linkingTelegram,
  }) => AccountState(
    signedIn: signedIn ?? this.signedIn,
    subscription: subscription == null ? this.subscription : subscription(),
    profile: profile ?? this.profile,
    devices: devices ?? this.devices,
    inactive: inactive ?? this.inactive,
    refreshing: refreshing ?? this.refreshing,
    linkingTelegram: linkingTelegram ?? this.linkingTelegram,
  );
}

/// How «Привязать Telegram» ended, for the tab to tell.
sealed class TelegramLinkOutcome {
  const TelegramLinkOutcome();
}

final class TelegramLinked extends TelegramLinkOutcome {
  const TelegramLinked(this.addedDays);

  /// What the Telegram side added to the subscription; 0 when nothing.
  final int addedDays;
}

final class TelegramLinkFailed extends TelegramLinkOutcome {
  const TelegramLinkFailed(this.error);

  /// [AccountError.cancelled] when the person turned Telegram down or tapped
  /// again.
  final AccountError error;
}

/// «Аккаунт»: the subscription, and for a signed-in person the account, its
/// devices and the way out. Home's «Лимит устройств» uses the same devices.
final class AccountController extends PageCubit<AccountState> {
  AccountController({
    required this._account,
    required this._openLink,
    this._database,
    SubscriptionRefresh? refreshSubscription,
  }) : _refreshSubscription =
           refreshSubscription ??
           SubscriptionService().refreshSubscriptionResult,
       super(
         AccountState(
           signedIn: _account.signedIn.value,
           inactive: _account.subscriptionMissing,
         ),
       ) {
    _account.signedIn.addListener(_sessionChanged);
  }

  final AccountService _account;

  /// The queue incoming links go through, which adds a subscription.
  final void Function(Uri) _openLink;
  final AppDatabase? _database;
  final SubscriptionRefresh _refreshSubscription;
  StreamSubscription<SubscriptionData?>? _rows;

  // Opened on first use: Home builds this controller before it needs it.
  AppDatabase get _db => _database ?? AppDatabase();

  void _sessionChanged() {
    final signedIn = _account.signedIn.value;
    if (signedIn == state.signedIn) return;
    // A new session loads its own data; an ended one keeps none.
    emit(
      AccountState(
        signedIn: signedIn,
        subscription: state.subscription,
        inactive: _account.subscriptionMissing,
      ),
    );
    if (signedIn) unawaited(refresh());
  }

  /// Loads everything the tab shows. The subscription is refreshed here too,
  /// and one the account has but the device lacks goes to the add path.
  Future<void> refresh() async {
    if (state.refreshing) return;
    emit(state.copyWith(refreshing: true));
    try {
      await _refresh();
    } finally {
      emit(state.copyWith(refreshing: false));
    }
  }

  Future<void> _refresh() async {
    _rows ??= _db.subscriptionDao.allRowsStream
        .map((rows) => rows.lastOrNull)
        .listen(
          (row) => emit(state.copyWith(subscription: () => row)),
          onError: (Object error) => ygLogger(
            'read account subscription failed (${error.runtimeType})',
          ),
        );
    final row = (await _db.subscriptionDao.allRows).lastOrNull;
    if (isClosed) return;
    emit(state.copyWith(subscription: () => row));
    if (!state.signedIn) {
      if (row != null) await _refreshQuietly(row);
      return;
    }
    await Future.wait([
      _loadProfile(),
      loadDevices(),
      _load(_account.accountSubscription, (link) {
        // The stream keeps the row current, unlike [row] read before.
        if (link != null && state.subscription == null) _openLink(link);
        return state.copyWith(inactive: link == null);
      }),
      if (row != null) _refreshQuietly(row),
    ]);
  }

  Future<void> _loadProfile() =>
      _load(_account.profile, (profile) => state.copyWith(profile: profile));

  /// The account's devices alone, as «Лимит устройств» lists them.
  Future<void> loadDevices() => state.signedIn
      ? _load(_account.devices, (devices) => state.copyWith(devices: devices))
      : Future.value();

  /// Takes [device] off the subscription. False when the backend refused.
  Future<bool> removeDevice(AccountDevice device) async {
    try {
      await _account.removeDevice(device.hwid);
    } on AccountException catch (error) {
      ygLogger('remove device failed (${error.error.name})');
      return false;
    }
    if (state.devices case final devices?) {
      emit(state.copyWith(devices: devices.without(device.hwid)));
    }
    return true;
  }

  /// «Привязать Telegram»: Telegram's page opens in the browser, and the tab
  /// stays usable until the person comes back with its code. The merged
  /// account then replaces the session, and its subscription the one here
  /// when it changed.
  Future<TelegramLinkOutcome> linkTelegram() async {
    if (state.linkingTelegram) {
      return const TelegramLinkFailed(AccountError.cancelled);
    }
    try {
      final code = await _account.openTelegramLink();
      emit(state.copyWith(linkingTelegram: true));
      try {
        final linked = await _account.exchangeTelegramLink(code);
        await _reloadLinked(linked);
        return TelegramLinked(linked.addedDays);
      } finally {
        if (!isClosed) emit(state.copyWith(linkingTelegram: false));
      }
    } on AccountException catch (error) {
      if (error.error != AccountError.alreadyLinked) {
        return TelegramLinkFailed(error.error);
      }
      // Linked meanwhile, on the site or in another attempt.
      await _loadProfile();
      return const TelegramLinked(0);
    } catch (error) {
      ygLogger('link Telegram failed (${error.runtimeType})');
      return const TelegramLinkFailed(AccountError.unexpected);
    }
  }

  /// What linking changed: the subscription, which got the days, and the
  /// profile, which now has Telegram.
  Future<void> _reloadLinked(TelegramLink linked) async {
    if (linked.subscription case final link?) {
      _openLink(link);
    } else if (state.subscription case final row?) {
      await _refreshQuietly(row);
    }
    await Future.wait([_loadProfile(), loadDevices()]);
    if (!isClosed) {
      emit(state.copyWith(inactive: _account.subscriptionMissing));
    }
  }

  /// Signs out. The gate then shows «Вход» unless a subscription from a link
  /// remains.
  Future<void> logout() => _account.logout();

  /// Runs one request of [refresh]; a failure leaves the rest of the tab.
  Future<void> _load<T>(
    Future<T> Function() request,
    AccountState Function(T) apply,
  ) async {
    try {
      final value = await request();
      if (!isClosed && state.signedIn) emit(apply(value));
    } on AccountException catch (error) {
      ygLogger('load account failed (${error.error.name})');
    }
  }

  Future<void> _refreshQuietly(SubscriptionData row) async {
    try {
      await _refreshSubscription(row);
    } catch (error) {
      ygLogger('refresh account subscription failed (${error.runtimeType})');
    }
  }

  @override
  Future<void> disposePageResources() async {
    _account.signedIn.removeListener(_sessionChanged);
    await _rows?.cancel();
  }
}
