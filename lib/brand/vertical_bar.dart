import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';

/// Where iOS puts its vertical bar, kept current by the App's iOS side. Null
/// on other systems and wherever iOS lays its bars out across the screen.
ValueListenable<VerticalBar?> get verticalBar => _watch.bar;

final _watch = _VerticalBarWatch();

final class _VerticalBarWatch implements VerticalBarFlutterApi {
  _VerticalBarWatch() {
    if (!Platform.isIOS) return;
    VerticalBarFlutterApi.setUp(this);
    unawaited(
      VerticalBarHostApi().watchVerticalBar().catchError((Object error) {
        ygLogger('watch vertical bar failed (${error.runtimeType})');
      }),
    );
  }

  final bar = ValueNotifier<VerticalBar?>(null);

  @override
  void verticalBarChanged(VerticalBar? bar) => this.bar.value = bar;
}
