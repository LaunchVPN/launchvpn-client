import 'package:flutter/cupertino.dart' show RefreshIndicatorMode;
import 'package:material_ui/material_ui.dart';

/// What the screens that refresh on a pull share.
abstract final class BrandPull {
  /// A pull needs the overscroll Android does not have.
  static const physics = BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  /// How far a pull has gone toward refreshing: full once it has.
  static double progress(
    RefreshIndicatorMode mode,
    double pulledExtent,
    double refreshTriggerPullDistance,
  ) => mode == RefreshIndicatorMode.drag
      ? (pulledExtent / refreshTriggerPullDistance).clamp(0.0, 1.0)
      : 1;
}
