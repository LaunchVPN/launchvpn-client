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
}
