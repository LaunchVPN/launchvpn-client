import 'dart:math';

import 'package:flutter/cupertino.dart' show RefreshIndicatorMode;
import 'package:flutter/rendering.dart';
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

/// Keeps [child] where it rests while the scroll view it is in is pulled past
/// its top, so only the content above it follows the pull.
///
/// The position is read as the child paints: the refresh indicator corrects
/// it during layout, after any rebuild.
class PinnedOnPull extends SingleChildRenderObjectWidget {
  const PinnedOnPull({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPinnedOnPull(Scrollable.of(context).position);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPinnedOnPull renderObject,
  ) => renderObject.position = Scrollable.of(context).position;
}

class RenderPinnedOnPull extends RenderProxyBox {
  RenderPinnedOnPull(this._position);

  ScrollPosition _position;

  set position(ScrollPosition value) {
    if (value == _position) return;
    if (attached) {
      _position.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _position = value;
    markNeedsPaint();
  }

  /// Up by as far as the content is pulled down.
  Offset get _shift =>
      Offset(0, _position.hasPixels ? min(_position.pixels, 0) : 0);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _position.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      super.paint(context, offset + _shift);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _shift,
        position: position,
        hitTest: (result, transformed) =>
            super.hitTestChildren(result, position: transformed),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
}
