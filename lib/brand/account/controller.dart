import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/service.dart';
import 'package:onexray/service/account/telegram_auth.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';

final class AccountState {
  const AccountState({
    this.signedIn = false,
    this.subscription,
    this.details,
    this.devices,
    this.subscriptionMaxDevices,
    this.inactive = false,
    this.refreshing = false,
    this.linkingTelegram = false,
    this.resumedLink,
    this.deletingAccount = false,
  });

  final bool signedIn;

  /// The subscription on this device, the account's or one from a link.
  final SubscriptionData? subscription;

  /// Null until loaded, and from a link only.
  final AccountDetails? details;

  /// Null until loaded, and from a link only.
  final AccountDevices? devices;

  /// The devices the panel allows this user, when the subscription says.
  final int? subscriptionMaxDevices;

  /// How many devices the subscription allows: the user's own limit, else
  /// the one the device list names. Null when neither sets one.
  int? get deviceLimit => subscriptionMaxDevices ?? devices?.max;

  /// The account has no active subscription.
  final bool inactive;

  /// [AccountController.refresh] is running.
  final bool refreshing;

  /// Back from Telegram, the App is linking it with the code it brought.
  final bool linkingTelegram;

  /// How a link the system closed the App during ended, until the tab told
  /// it.
  final TelegramLinkOutcome? resumedLink;

  /// [AccountController.deleteAccount] is running.
  final bool deletingAccount;

  /// Days and traffic as the panel last reported them.
  SubscriptionUserInfo? get usage => switch (subscription) {
    final row? => SubscriptionUserInfo.fromSubscription(row),
    null => null,
  };

  AccountState copyWith({
    bool? signedIn,
    SubscriptionData? Function()? subscription,
    AccountDetails? Function()? details,
    AccountDevices? Function()? devices,
    int? subscriptionMaxDevices,
    bool? inactive,
    bool? refreshing,
    bool? linkingTelegram,
    TelegramLinkOutcome? Function()? resumedLink,
    bool? deletingAccount,
  }) => AccountState(
    signedIn: signedIn ?? this.signedIn,
    subscription: subscription == null ? this.subscription : subscription(),
    details: details == null ? this.details : details(),
    devices: devices == null ? this.devices : devices(),
    subscriptionMaxDevices:
        subscriptionMaxDevices ?? this.subscriptionMaxDevices,
    inactive: inactive ?? this.inactive,
    refreshing: refreshing ?? this.refreshing,
    linkingTelegram: linkingTelegram ?? this.linkingTelegram,
    resumedLink: resumedLink == null ? this.resumedLink : resumedLink(),
    deletingAccount: deletingAccount ?? this.deletingAccount,
  );
}

/// How «Удалить аккаунт» ended.
enum AccountDeletion {
  deleted,

  /// The session was already gone: nothing was deleted, the device signed
  /// out, and the person signs in again to delete the account.
  signInAgain,

  /// The backend could not delete the account, which stays signed in.
  failed,
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
    SubscriptionLinkService? subscriptions,
    SubscriptionRefresh? refreshSubscription,
    ValueListenable<bool>? deviceLimit,
  }) : _subscriptions = subscriptions ?? SubscriptionLinkService(),
       _refreshSubscription =
           refreshSubscription ??
           SubscriptionService().refreshSubscriptionResult,
       _deviceLimit = deviceLimit ?? SubscriptionService().deviceLimitReached,
       super(
         AccountState(
           signedIn: _account.session.signedIn.value,
           inactive: _account.data.subscriptionMissing,
         ),
       ) {
    _account.session.signedIn.addListener(_sessionChanged);
    // A restored session: Home tells an ended account before the tab opens.
    if (state.signedIn) unawaited(_loadSubscription());
    if (_account.telegram.browser.resume(TelegramAuthPurpose.link)
        case final code?) {
      unawaited(_resumeLink(code));
    }
  }

  final AccountService _account;

  /// The subscription on this device.
  final SubscriptionLinkService _subscriptions;
  final SubscriptionRefresh _refreshSubscription;

  /// The panel last refused this device: the subscription has all its
  /// devices.
  final ValueListenable<bool> _deviceLimit;
  StreamSubscription<SubscriptionData?>? _rows;

  /// The session the tab's account data comes from. Signing in or out and a
  /// Telegram merge start a new one; answers to an older one are dropped.
  int _session = 0;

  void _sessionChanged() {
    final signedIn = _account.session.signedIn.value;
    if (signedIn == state.signedIn) return;
    _session++;
    // A new session loads its own data; an ended one keeps none.
    emit(
      AccountState(
        signedIn: signedIn,
        subscription: state.subscription,
        inactive: _account.data.subscriptionMissing,
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
    _rows ??= _subscriptions.watchCurrent().listen(
      (row) => emit(state.copyWith(subscription: () => row)),
      onError: (Object error) =>
          ygLogger('read account subscription failed (${error.runtimeType})'),
    );
    final row = await _subscriptions.current();
    if (isClosed) return;
    emit(state.copyWith(subscription: () => row));
    if (!state.signedIn) {
      if (row != null) await _refreshQuietly(row);
      return;
    }
    final session = _session;
    final subscription = _loadSubscription();
    await Future.wait([
      _loadDetails(),
      loadDevices(),
      subscription,
      if (row != null) _refreshQuietly(row),
    ]);
    // The stream keeps the row current, unlike [row] read before.
    if (await subscription case final missing?
        when session == _session && state.subscription == null && _placeFree) {
      _account.data.addSubscription(missing);
    }
  }

  /// Reads whether the account's subscription is active, and the devices it
  /// allows. Its link; null when there is none or the read failed.
  Future<SubscriptionDeepLink?> _loadSubscription() async {
    SubscriptionDeepLink? link;
    await _load(_account.data.subscription, (subscription) {
      link = subscription.link;
      return state.copyWith(
        inactive: link == null,
        subscriptionMaxDevices: subscription.maxDevices,
      );
    });
    return link;
  }

  /// Whether the panel may take this device now. After it refused the
  /// device over the limit, adding the subscription again would only repeat
  /// the refusal until the list shows a free place.
  bool get _placeFree {
    if (!_deviceLimit.value) return true;
    final (devices, limit) = (state.devices, state.deviceLimit);
    return devices != null && (limit == null || devices.items.length < limit);
  }

  Future<bool> _loadDetails() => _load(
    _account.data.details,
    (details) => state.copyWith(details: () => details),
  );

  /// The account's devices alone, as «Лимит устройств» lists them. Whether
  /// they loaded.
  Future<bool> loadDevices() => state.signedIn
      ? _load(
          _account.data.devices,
          (devices) => state.copyWith(devices: () => devices),
        )
      : Future.value(false);

  /// Takes [device] off the subscription. False when the backend refused.
  Future<bool> removeDevice(AccountDevice device) async {
    try {
      await _account.data.removeDevice(device.hwid);
    } on AccountException catch (error) {
      ygLogger('remove device failed (${error.error.name})');
      return false;
    }
    if (state.devices case final devices?) {
      emit(state.copyWith(devices: () => devices.without(device.hwid)));
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
    return _finishLink(_account.telegram.openLink());
  }

  /// A link the system closed the App during, finished with the code
  /// [pending] brings back. Its outcome waits in [AccountState.resumedLink].
  Future<void> _resumeLink(Future<TelegramCode> pending) async {
    final outcome = await _finishLink(pending);
    if (isClosed) return;
    // Another attempt replaced it, which tells its own outcome.
    if (outcome case TelegramLinkFailed(error: AccountError.cancelled)) return;
    emit(state.copyWith(resumedLink: () => outcome));
  }

  /// The tab told [AccountState.resumedLink].
  void resumedLinkShown() => emit(state.copyWith(resumedLink: () => null));

  /// Links Telegram with the code [pending] brings back.
  Future<TelegramLinkOutcome> _finishLink(Future<TelegramCode> pending) async {
    try {
      final code = await pending;
      emit(state.copyWith(linkingTelegram: true));
      try {
        final linked = await _account.telegram.exchangeLink(code);
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
      await _loadDetails();
      return const TelegramLinked(0);
    } catch (error) {
      ygLogger('link Telegram failed (${error.runtimeType})');
      return const TelegramLinkFailed(AccountError.unexpected);
    }
  }

  /// What linking changed: the subscription, which got the days, and the
  /// account details, which now have Telegram. The merge may have handed the
  /// session to another account, so what fails to load is no longer shown.
  Future<void> _reloadLinked(TelegramLink linked) async {
    final session = ++_session;
    if (!linked.replacedSubscription) {
      if (state.subscription case final row?) await _refreshQuietly(row);
    }
    final [details, devices] = await Future.wait([
      _loadDetails(),
      loadDevices(),
    ]);
    if (isClosed || session != _session) return;
    emit(
      state.copyWith(
        details: details ? null : () => null,
        devices: devices ? null : () => null,
        inactive: _account.data.subscriptionMissing,
      ),
    );
  }

  /// Signs out. The gate then shows «Вход» unless a subscription from a link
  /// remains.
  Future<void> logout() => _account.data.logout();

  /// «Удалить аккаунт». Once deleted the gate shows «Вход» as after
  /// [logout]. A session already gone signs out the same way and asks to
  /// sign in again; [AccountState.subscription] then says whether a
  /// subscription from a link keeps the tabs.
  Future<AccountDeletion> deleteAccount() async {
    emit(state.copyWith(deletingAccount: true));
    try {
      await _account.data.deleteAccount();
      return AccountDeletion.deleted;
    } on AccountException catch (error) {
      ygLogger('delete account failed (${error.error.name})');
      if (error.error != AccountError.signedOut) return AccountDeletion.failed;
      // Read now: the stream may not have seen the removal yet.
      final row = await _subscriptions.current();
      if (!isClosed) emit(state.copyWith(subscription: () => row));
      return AccountDeletion.signInAgain;
    } finally {
      if (!isClosed) emit(state.copyWith(deletingAccount: false));
    }
  }

  /// Runs one request of [refresh]; a failure leaves the rest of the tab.
  /// Whether its answer, still for the current session, was applied.
  Future<bool> _load<T>(
    Future<T> Function() request,
    AccountState Function(T) apply,
  ) async {
    final session = _session;
    try {
      final value = await request();
      if (isClosed || session != _session) return false;
      emit(apply(value));
      return true;
    } on AccountException catch (error) {
      ygLogger('load account failed (${error.error.name})');
      return false;
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
    _account.session.signedIn.removeListener(_sessionChanged);
    await _rows?.cancel();
  }
}
