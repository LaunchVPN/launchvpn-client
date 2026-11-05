import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/servers/subscription/deep_link.dart';

enum AccessGateState {
  /// The subscription table has not answered yet.
  checking,

  /// Neither a session nor a subscription: «Вход» replaces the tabs.
  login,
  tabs,
}

/// Whether the person sees «Вход» or the tabs. A session or a subscription,
/// from the account or from a link, is enough for the tabs.
final class AccessGateController extends PageCubit<AccessGateState> {
  AccessGateController({required this._signedIn, Stream<bool>? hasSubscription})
    : super(AccessGateState.checking) {
    _signedIn.addListener(_update);
    _subscription = (hasSubscription ?? _watchSubscription()).listen(
      (value) {
        _hasSubscription = value;
        _update();
      },
      onError: (Object error) {
        ygLogger('read subscriptions failed (${error.runtimeType})');
        // Home explains a missing subscription better than a login would.
        _hasSubscription = true;
        _update();
      },
    );
  }

  final ValueListenable<bool> _signedIn;
  late final StreamSubscription<bool> _subscription;
  bool? _hasSubscription;

  /// Whether the device has a subscription, as the database changes.
  static Stream<bool> _watchSubscription() => SubscriptionLinkService()
      .watchCurrent()
      .map((row) => row != null)
      .distinct();

  void _update() {
    final hasSubscription = _hasSubscription;
    if (hasSubscription == null) return;
    emit(
      _signedIn.value || hasSubscription
          ? AccessGateState.tabs
          : AccessGateState.login,
    );
  }

  @override
  Future<void> disposePageResources() async {
    _signedIn.removeListener(_update);
    await _subscription.cancel();
  }
}
