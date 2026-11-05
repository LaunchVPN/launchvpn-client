import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/account/device_claim.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/session.dart';
import 'package:onexray/service/account/session_store.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';

/// What the signed-in account holds: its subscription on this device, its
/// details and devices, the trial, and the ways out, signing out and
/// deletion.
final class AccountData {
  AccountData({
    required this._session,
    required this._store,
    required this._device,
    required this._addSubscription,
    required this._removeSubscription,
  });

  final AccountSession _session;
  final AccountSessionStore _store;
  final Future<DeviceClaim> Function() _device;

  /// The queue system links take, so the account's subscription is
  /// confirmed, added and reported as one from a link is.
  final void Function(Uri link) _addSubscription;
  final Future<void> Function(String url) _removeSubscription;
  bool _subscriptionMissing = false;
  bool _unfinishedDeletion = false;

  /// The account had no active subscription when this session last read it,
  /// the trial included. False until read, signed out, and after a restart.
  bool get subscriptionMissing =>
      _session.signedIn.value && _subscriptionMissing;

  /// Keeps the session from a token pair answer, then reads the account's
  /// subscription and adds it once signed in. An account without one claims
  /// the trial, which the backend refuses to one that had it, unless the
  /// answer says the trial already started. Only the code from the email
  /// says so; a login cannot tell an account that never had a subscription
  /// from an ended one.
  Future<void> signIn(Map<String, Object?> answer) async {
    final trialStarted = answer['trialGranted'] == true;
    final link = await _session.start(answer, () {
      _unfinishedDeletion = false;
      _subscriptionMissing = false;
      return _readQuietly(
        () async =>
            await _subscriptionLink() ??
            (trialStarted ? null : await _claimTrial()),
      );
    });
    if (link != null) addSubscription(link);
  }

  /// The account's subscription, its link marked as the account's.
  Future<AccountSubscription> subscription() async {
    final data = await _session.get('/api/subscription');
    final maxDevices = switch (data['maxDevices']) {
      final int max when max > 0 => max,
      _ => null,
    };
    final configLink = data['configLink'];
    _subscriptionMissing =
        data['active'] != true || configLink is! String || configLink.isEmpty;
    if (configLink is! String || _subscriptionMissing) {
      return AccountSubscription(maxDevices: maxDevices);
    }
    final link = SubscriptionDeepLink.fromUrl(configLink);
    if (link == null) throw const AccountException(AccountError.unexpected);
    await _store.saveSubscriptionUrl(link.url);
    return AccountSubscription(link: link, maxDevices: maxDevices);
  }

  /// Sends the account's subscription [link] down the queue system links
  /// take.
  void addSubscription(SubscriptionDeepLink link) => _addSubscription(link.uri);

  /// The URL of the subscription the account brought to this device.
  Future<String?> savedSubscriptionUrl() => _store.readSubscriptionUrl();

  /// After a merge handed the session to another account: reads its
  /// subscription, and a changed one replaces [previous], the
  /// [savedSubscriptionUrl] from before, on the device. Whether it changed.
  Future<bool> replaceAfterMerge(String? previous) async {
    final current = await _readQuietly(_subscriptionLink);
    final changed = current != null && current.url != previous;
    if (changed && previous != null) {
      try {
        await _removeSubscription(previous);
      } catch (error) {
        ygLogger('remove account subscription failed (${error.runtimeType})');
      }
    }
    if (changed) addSubscription(current);
    return changed;
  }

  /// What the backend knows about the account.
  Future<AccountDetails> details() async =>
      AccountDetails.fromJson(await _session.get('/api/me'));

  /// The devices on the account's subscription, this one marked.
  Future<AccountDevices> devices() async {
    final device = await _device();
    return AccountDevices.fromJson(
      await _session.get('/api/devices'),
      currentHwid: device.hwid,
    );
  }

  /// Takes another device off the subscription, which frees its place.
  Future<void> removeDevice(String hwid) => _session.post(
    '/api/devices/disconnect',
    data: {'hwid': hwid},
    auth: AccountAuth.bearer,
  );

  /// Revokes this device's session and removes the subscription the account
  /// brought, keeping one added from a link. Signs out here even when the
  /// backend cannot be reached.
  Future<void> logout() async {
    try {
      await _session.post('/api/app/auth/logout', auth: AccountAuth.bearer);
    } on AccountException catch (error) {
      ygLogger('revoke account session failed (${error.error.name})');
    }
    await _forget();
  }

  /// Deletes the account on the backend, then forgets it here as [logout]
  /// does. Throws [AccountException] and stays signed in when the deletion
  /// did not happen. A session the backend refuses even after a refresh
  /// deletes nothing: it signs out here, throws [AccountError.signedOut] and
  /// leaves [takeUnfinishedDeletion] for «Вход».
  Future<void> deleteAccount() async {
    try {
      await _session.post(
        '/api/app/account/delete',
        data: const <String, Object?>{},
        auth: AccountAuth.bearer,
      );
    } on AccountException catch (error) {
      if (error.error != AccountError.signedOut) rethrow;
      // Before signing out: «Вход» may open as soon as the session ends.
      _unfinishedDeletion = true;
      await _forget();
      rethrow;
    }
    await _forget();
  }

  /// Whether a deletion found the session gone since the last sign-in, so
  /// the person signs in again to delete the account. Reading clears it.
  bool takeUnfinishedDeletion() {
    final unfinished = _unfinishedDeletion;
    _unfinishedDeletion = false;
    return unfinished;
  }

  Future<SubscriptionDeepLink?> _subscriptionLink() async =>
      (await subscription()).link;

  Future<SubscriptionDeepLink?> _claimTrial() async {
    final device = await _device();
    try {
      await _session.post(
        '/api/app/trial',
        data: {'hwid': device.hwid},
        auth: AccountAuth.bearer,
      );
    } on AccountException catch (error) {
      ygLogger('claim trial failed (${error.error.name})');
      return null;
    }
    return _subscriptionLink();
  }

  /// What [read] makes of the account's subscription; null when the backend
  /// could not tell, which only the log keeps.
  static Future<SubscriptionDeepLink?> _readQuietly(
    Future<SubscriptionDeepLink?> Function() read,
  ) async {
    try {
      return await read();
    } on AccountException catch (error) {
      ygLogger('read account subscription failed (${error.error.name})');
      return null;
    }
  }

  /// Removes the subscription the account brought and signs out here.
  Future<void> _forget() async {
    try {
      if (await _store.readSubscriptionUrl() case final url?) {
        await _removeSubscription(url);
        await _store.clearSubscriptionUrl();
      }
    } catch (error) {
      ygLogger('remove account subscription failed (${error.runtimeType})');
    }
    await _session.end();
  }
}
