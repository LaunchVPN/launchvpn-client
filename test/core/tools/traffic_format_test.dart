import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/tools/traffic_format.dart';

void main() {
  test('localized traffic keeps whole bytes and one decimal above', () {
    expect(localizedTraffic(512, 'en'), (number: '512', unit: TrafficUnit.b));
    expect(localizedTraffic(1536, 'ru'), (number: '1,5', unit: TrafficUnit.kb));
    expect(localizedTraffic(3 * 1024 * 1024 * 1024, 'en'), (
      number: '3',
      unit: TrafficUnit.gb,
    ));
  });

  test('localized traffic stops at terabytes', () {
    expect(
      localizedTraffic(2048 * 1024 * 1024 * 1024 * 1024, 'en').unit,
      TrafficUnit.tb,
    );
  });
}
