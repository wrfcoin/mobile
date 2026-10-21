import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/wrf_forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/hdd_cdd_card.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/wrf_forecast_chart.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

WrfForecastModel _makeModel({bool isSimulated = false}) {
  return WrfForecastModel(
    location: 'Test City',
    generatedAt: '2026-04-11T08:00:00Z',
    ipfsCid: 'QmAbcDefGhiJklMnoPqr',
    isSimulated: isSimulated,
    hourly: List.generate(12, (i) {
      final ts = DateTime.utc(2026, 4, 11, i);
      final tempC = 16.0 + i.toDouble();
      return WrfForecastPoint(
        timestamp: ts.toIso8601String(),
        temperatureC: tempC,
        temperatureMaxC: tempC + 1,
        temperatureMinC: tempC - 1,
        precipitationMm: i % 3 == 0 ? 0.5 : 0.0,
        windSpeedMs: 3.0 + i * 0.2,
        forecastConfidence: 0.85,
        hdd: tempC < 18.3 ? 18.3 - tempC : 0.0,
        cdd: tempC > 18.3 ? tempC - 18.3 : 0.0,
      );
    }),
  );
}

Widget _wrapInApp(Widget child) {
  return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
}

// ---------------------------------------------------------------------------
// WrfForecastChart tests
// ---------------------------------------------------------------------------

void main() {
  group('WrfForecastChart', () {
    testWidgets('renders without overflow with live data', (tester) async {
      await tester.pumpWidget(_wrapInApp(
        WrfForecastChart(forecast: _makeModel()),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('shows LIVE (WRF) badge when isSimulated = false', (tester) async {
      await tester.pumpWidget(_wrapInApp(
        WrfForecastChart(forecast: _makeModel()),
      ));
      await tester.pump();

      expect(find.text('LIVE (WRF)'), findsOneWidget);
      expect(find.text('SIMULATED'), findsNothing);
    });

    testWidgets('shows SIMULATED badge when isSimulated = true', (tester) async {
      await tester.pumpWidget(_wrapInApp(
        WrfForecastChart(forecast: _makeModel(isSimulated: true)),
      ));
      await tester.pump();

      expect(find.text('SIMULATED'), findsOneWidget);
      expect(find.text('LIVE (WRF)'), findsNothing);
    });

    testWidgets('renders empty state when hourly list is empty', (tester) async {
      const emptyModel = WrfForecastModel(
        location: 'Empty',
        generatedAt: '2026-04-11T00:00:00Z',
        ipfsCid: 'QmEmpty',
      );
      await tester.pumpWidget(_wrapInApp(
        const WrfForecastChart(forecast: emptyModel),
      ));
      await tester.pump();

      expect(find.text('No WRF forecast data'), findsOneWidget);
    });

    testWidgets('has accessible semantics label', (tester) async {
      await tester.pumpWidget(_wrapInApp(
        WrfForecastChart(forecast: _makeModel()),
      ));
      await tester.pump();

      final semanticsNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'WRF forecast chart')),
      );
      expect(semanticsNode, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // HddCddCard tests
  // ---------------------------------------------------------------------------

  group('HddCddCard', () {
    testWidgets('renders without overflow', (tester) async {
      await tester.pumpWidget(_wrapInApp(
        HddCddCard(forecast: _makeModel()),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('IPFS CID chip is tappable and shows snackbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HddCddCard(forecast: _makeModel()),
          ),
        ),
      );
      await tester.pump();

      // The chip text is the truncated CID.
      final chipFinder = find.byType(GestureDetector).first;
      await tester.tap(chipFinder);
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('shows LIVE (WRF) badge when isSimulated = false', (tester) async {
      await tester.pumpWidget(_wrapInApp(
        HddCddCard(forecast: _makeModel()),
      ));
      await tester.pump();

      expect(find.text('LIVE (WRF)'), findsOneWidget);
    });

    testWidgets('shows SIMULATED badge when isSimulated = true', (tester) async {
      await tester.pumpWidget(_wrapInApp(
        HddCddCard(forecast: _makeModel(isSimulated: true)),
      ));
      await tester.pump();

      expect(find.text('SIMULATED'), findsOneWidget);
    });
  });
}
