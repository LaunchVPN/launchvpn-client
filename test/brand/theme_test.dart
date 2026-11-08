import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/brand/theme.dart';

void main() {
  test('the wide buttons write their label in the card title style', () {
    for (final style in [
      BrandTheme.primaryButton,
      BrandTheme.secondaryButton,
      BrandTheme.dangerButton,
      BrandTheme.quietButton,
      BrandTheme.linkButton,
    ]) {
      expect(style.textStyle?.resolve({}), BrandText.cardTitle);
    }
  });

  testWidgets('motion stops when the system asks for less of it', (
    tester,
  ) async {
    final durations = <bool, Duration>{};
    for (final reduced in [false, true]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Builder(
            builder: (context) {
              durations[reduced] = BrandMotion.of(context, BrandMotion.slow);
              return const SizedBox();
            },
          ),
        ),
      );
    }

    expect(durations, {
      false: const Duration(milliseconds: 400),
      true: Duration.zero,
    });
  });
}
