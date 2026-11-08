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

/// Lays [child] at the bottom of the space it is given and keeps it there while
/// the scroll view it is in is pulled past its top, so only the content above
/// follows the pull. Once the pull has used up that space, the content pushes
/// the child along instead of sliding over it.
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

class RenderPinnedOnPull extends RenderShiftedBox {
  RenderPinnedOnPull(this._position) : super(null);

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

  /// Where the child rests, up by as far as the content is pulled down, but
  /// never above this box.
  Offset get _childOffset {
    final rest = (child!.parentData! as BoxParentData).offset;
    final pulled = _position.hasPixels ? min(_position.pixels, 0.0) : 0.0;
    return rest.translate(0, max(pulled, -rest.dy));
  }

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
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(child!.getDryLayout(constraints.loosen()));

  @override
  void performLayout() {
    final child = this.child!
      ..layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(child.size);
    (child.parentData! as BoxParentData).offset = Offset(
      (size.width - child.size.width) / 2,
      size.height - child.size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(child!, offset + _childOffset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _childOffset,
        position: position,
        hitTest: (result, transformed) =>
            child!.hitTest(result, position: transformed),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = _childOffset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }
}
