import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// How visible the one widget [finder] matches is, through every fade above
/// it: 1 is fully shown.
double shownOpacity(WidgetTester tester, Finder finder) => tester
    .widgetList(
      find.ancestor(
        of: finder,
        matching: find.byWidgetPredicate(
          (widget) => widget is FadeTransition || widget is Opacity,
        ),
      ),
    )
    .fold(
      1.0,
      (shown, widget) =>
          shown *
          switch (widget) {
            FadeTransition(:final opacity) => opacity.value,
            Opacity(:final opacity) => opacity,
            _ => 1,
          },
    );
