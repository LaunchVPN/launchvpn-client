import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/settings/tunnel_memory.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/tester/tunnel_memory.dart';

void main() {
  const mb = 1 << 20;

  /// A service whose extension answers with [readings] in turn, the last one
  /// from then on, and counts the reads.
  ({TunnelMemoryService service, List<int> reads}) fake({
    required bool testFlight,
    required List<TunnelMemory?> readings,
  }) {
    final reads = <int>[0];
    final service = TunnelMemoryService(
      isTestFlight: () async => testFlight,
      read: () async {
        final index = reads[0]++;
        return readings[index < readings.length ? index : readings.length - 1];
      },
    );
    return (service: service, reads: reads);
  }

  Future<void> pump(WidgetTester tester, TunnelMemoryService service) =>
      tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TunnelMemoryLine(service: service)),
        ),
      );

  TunnelMemory reading(double footprint, double peak) => TunnelMemory(
    footprint: (footprint * mb).round(),
    peak: (peak * mb).round(),
    limit: 50 * mb,
  );

  testWidgets('a TestFlight build shows the memory and follows it', (
    tester,
  ) async {
    final extension = fake(
      testFlight: true,
      readings: [reading(18.4, 27), reading(21, 31.6)],
    );
    await pump(tester, extension.service);
    await tester.pump();

    expect(
      find.text('Память VPN 18,4, пик 27,0, запас 23,0 МБ'),
      findsOneWidget,
    );

    await tester.pump(TunnelMemoryController.interval);
    expect(
      find.text('Память VPN 21,0, пик 31,6, запас 18,4 МБ'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    final reads = extension.reads[0];
    await tester.pump(TunnelMemoryController.interval * 3);
    expect(extension.reads[0], reads, reason: 'stops once the screen closes');
  });

  testWidgets('shows nothing while no tunnel runs', (tester) async {
    final extension = fake(testFlight: true, readings: [null]);
    await pump(tester, extension.service);
    await tester.pump();

    expect(find.textContaining('Память VPN'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an App Store build never asks the tunnel', (tester) async {
    final extension = fake(testFlight: false, readings: [reading(18, 27)]);
    await pump(tester, extension.service);
    await tester.pump(TunnelMemoryController.interval * 2);

    expect(find.textContaining('Память VPN'), findsNothing);
    expect(extension.reads[0], 0);
    await tester.pumpWidget(const SizedBox());
  });
}
