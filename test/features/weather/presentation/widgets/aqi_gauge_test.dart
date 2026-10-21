import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/aqi_gauge.dart';

void main() {
  Future<void> pumpGauge(WidgetTester tester, int aqi) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: AqiGauge(aqi: aqi)),
        ),
      ),
    );
  }

  testWidgets('renders good AQI state', (tester) async {
    await pumpGauge(tester, 42);

    expect(find.text('42'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
  });

  testWidgets('renders unhealthy sensitive AQI label', (tester) async {
    await pumpGauge(tester, 125);

    expect(find.textContaining('Unhealthy'), findsOneWidget);
  });
}
