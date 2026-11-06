import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/connect/preset.dart';
import 'package:onexray/service/servers/locations.dart';
import 'package:onexray/service/settings/language/brand_language.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/menu/short_cut/service.dart';

/// Foreground Apple intents hand off to the existing App connection actions.
/// The Widget never compiles a configuration or directly starts a tunnel.
final class AppleWidgetService with WidgetsBindingObserver {
  static final _instance = AppleWidgetService._(
    AppPlatform.isIOS,
    AppFlutterApi().appleWidgetActions.stream,
    AppleWidgetHostApi().takeAction,
    AppleWidgetHostApi().setLanguage,
    ShortCutService().receive,
    AppleWidgetHostApi().setContext,
  );

  factory AppleWidgetService() => _instance;

  AppleWidgetService._(
    this._enabled,
    this._events,
    this._takeAction,
    this._setLanguage,
    this._receive,
    this._setContext,
  );

  @visibleForTesting
  factory AppleWidgetService.forTesting({
    bool enabled = true,
    required Stream<void> events,
    required Future<String?> Function() takeAction,
    required Future<void> Function(String) setLanguage,
    required Future<void> Function(String) receive,
    Future<void> Function(AppleWidgetContext)? setContext,
  }) => AppleWidgetService._(
    enabled,
    events,
    takeAction,
    setLanguage,
    receive,
    setContext ?? (_) async {},
  );

  final bool _enabled;
  final Stream<void> _events;
  final Future<String?> Function() _takeAction;
  final Future<void> Function(String) _setLanguage;
  final Future<void> Function(String) _receive;
  final Future<void> Function(AppleWidgetContext) _setContext;
  ({String? name, String? country, bool automatic, String? mode, int? ends})?
  _context;
  StreamSubscription<void>? _subscription;
  Future<void>? _draining;
  bool _needsDrain = false;

  Future<void> initialize() async {
    if (!_enabled) return;
    if (_subscription == null) {
      _subscription = _events.listen((_) => unawaited(_drain()));
      WidgetsBinding.instance.addObserver(this);
    }
    // Consume a cold-launch intent before automatic Connect is considered.
    await _drain();
  }

  Future<void> _drain() {
    _needsDrain = true;
    return _draining ??= _takeActions().whenComplete(() {
      _draining = null;
      if (_needsDrain && _subscription != null) unawaited(_drain());
    });
  }

  Future<void> _takeActions() async {
    try {
      while (_subscription != null) {
        _needsDrain = false;
        final action = await _takeAction();
        if (_subscription == null) return;
        if (action == 'startVpn' || action == 'stopVpn') {
          // Stop must not wait for an in-flight connection attempt to finish.
          unawaited(_receive(action!));
        }
        if (action == null && !_needsDrain) return;
      }
    } catch (error, stack) {
      _needsDrain = false;
      ygLogger('Apple widget action unavailable: $error\n$stack');
    }
  }

  /// Public URLs only navigate. Connection commands are private intent input.
  bool receiveOpenUri(Uri uri) {
    if (!_enabled || !isOpenUri(uri)) return false;
    unawaited(_receive(ShortCutAction.openConnect.name));
    return true;
  }

  static bool isOpenUri(Uri uri) =>
      uri.scheme == Brand.scheme &&
      uri.host == 'widget' &&
      uri.path == '/connect' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;

  Future<void> setLanguage(String languageCode) async {
    if (!_enabled) return;
    try {
      final code = BrandLanguage.of(LanguageCode.fromString(languageCode))
          .toLanguageTag();
      await _setLanguage(code);
    } catch (error, stack) {
      ygLogger('Apple widget language unavailable: $error\n$stack');
    }
  }

  /// Gives the Widget what Home shows: the location, the mode and when the
  /// subscription ends. Sends only changes.
  Future<void> setContext({
    required Location? location,
    required ConnectionPreset? preset,
    required DateTime? expiresAt,
  }) async {
    if (!_enabled) return;
    final context = (
      name: location?.name,
      country: location?.countryCode,
      automatic: location?.automatic ?? false,
      mode: preset?.name,
      ends: expiresAt?.millisecondsSinceEpoch,
    );
    if (context == _context) return;
    _context = context;
    try {
      await _setContext(
        AppleWidgetContext(
          location: context.name,
          countryCode: context.country,
          automatic: context.automatic,
          mode: context.mode,
          expiresAtMs: context.ends,
        ),
      );
    } catch (error, stack) {
      _context = null;
      ygLogger('Apple widget context unavailable: $error\n$stack');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_drain());
  }

  void dispose() {
    if (!_enabled) return;
    final subscription = _subscription;
    _subscription = null;
    _needsDrain = false;
    unawaited(subscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
  }
}
