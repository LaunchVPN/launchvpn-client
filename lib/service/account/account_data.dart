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
  bool _deleting = false;
  ForcedSignOut? _forcedSignOut;

  /// The account had no active subscription when this session last read it,
  /// the trial included. False until read, signed out, and after a restart.
  bool get subscriptionMissing =>
      _session.signedIn.value && _subscriptionMissing;

  /// Keeps the session from a token pair answer, then reads the account's
  /// subscription and adds it once signed in. An account without one claims
  /// the trial, which the backend refuses to one that had it, unless the
  /// answer says the trial already started or [trialAvailable] says there is
  /// none. Only the code from the email can tell; a login cannot tell an
  /// account that never had a subscription from an ended one.
  Future<void> signIn(
    Map<String, Object?> answer, {
    bool trialAvailable = true,
  }) async {
    final claimTrial = trialAvailable && answer['trialGranted'] != true;
    final link = await _session.start(answer, () {
      _forcedSignOut = null;
      _subscriptionMissing = false;
      return _readQuietly(
        () async =>
            await _subscriptionLink() ??
            (claimTrial ? await _claimTrial() : null),
      );
    });
    if (link != null) addSubscription(link);
  }

  /// The account's subscription, its link marked as the account's. A link
  /// other than the one the account brought, as after a merge, removes that
  /// one from the device.
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
    if (await _store.readSubscriptionUrl() case final brought?
        when brought != link.url) {
      await _removeQuietly(brought);
    }
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
  /// [savedSubscriptionUrl] from before, on the device. Whether it changed;
  /// a failed read leaves the replacement to the next [subscription].
  Future<bool> replaceAfterMerge(String? previous) async {
    final current = await _readQuietly(_subscriptionLink);
    final changed = current != null && current.url != previous;
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
  /// leaves [ForcedSignOut.deletionUnfinished] for «Вход».
  Future<void> deleteAccount() async {
    _deleting = true;
    try {
      await _session.post(
        '/api/app/account/delete',
        data: const <String, Object?>{},
        auth: AccountAuth.bearer,
      );
    } on AccountException catch (error) {
      if (error.error != AccountError.signedOut) rethrow;
      // Before signing out: «Вход» may open as soon as the session ends.
      _forcedSignOut = ForcedSignOut.deletionUnfinished;
      await _forget();
      rethrow;
    } finally {
      _deleting = false;
    }
    await _forget();
  }

  /// The backend ended the session on its own: removes the subscription the
  /// account brought, as [logout] does, and leaves the reason for «Вход».
  /// The session itself calls this, then signs out.
  Future<void> revoked() async {
    // Before signing out: «Вход» may open as soon as the session ends.
    _forcedSignOut = _deleting
        ? ForcedSignOut.deletionUnfinished
        : ForcedSignOut.sessionEnded;
    await _removeAccountSubscription();
  }

  /// Retries a sign-out that could not remove the subscription the account
  /// brought: signed out, its URL is still kept only then.
  Future<void> finishSignOut() async {
    if (!_session.signedIn.value) await _removeAccountSubscription();
  }

  /// Why the device signed out on its own since the last sign-in, for «Вход»
  /// to say. Reading clears it.
  ForcedSignOut? takeForcedSignOut() {
    final reason = _forcedSignOut;
    _forcedSignOut = null;
    return reason;
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
    await _removeAccountSubscription();
    await _session.end();
  }

  Future<void> _removeQuietly(String url) async {
    try {
      await _removeSubscription(url);
    } catch (error) {
      ygLogger('remove account subscription failed (${error.runtimeType})');
    }
  }

  Future<void> _removeAccountSubscription() async {
    try {
      if (await _store.readSubscriptionUrl() case final url?) {
        await _removeSubscription(url);
        await _store.clearSubscriptionUrl();
      }
    } catch (error) {
      ygLogger('remove account subscription failed (${error.runtimeType})');
    }
  }
}
