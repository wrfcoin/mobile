import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wrfcoin_mobile/features/social/weather_social_card.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/forecast_share_action.dart';

ForecastModel _sampleForecast() {
  return const ForecastModel(
    temperature: 23.4,
    humidity: 61,
    pressure: 1014.2,
    windSpeed: 4.8,
    windDirection: 'NW',
    precipitation: 0.6,
    location: 'Portland, OR',
    timestamp: '2026-04-09T12:30:00Z',
  );
}

Widget _host(Widget action) {
  return ProviderScope(
    overrides: [
      forecastShareRewardsProvider.overrideWith((ref) async => '12.34'),
    ],
    child: MaterialApp(
      home: Scaffold(appBar: AppBar(actions: [action])),
    ),
  );
}

void main() {
  Future<void> usePhoneViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('share action opens the weather card sheet with earned WRF', (
    tester,
  ) async {
    await usePhoneViewport(tester);
    await tester.pumpWidget(
      _host(ForecastShareAction(forecast: _sampleForecast())),
    );

    expect(find.byKey(ForecastShareAction.buttonKey), findsOneWidget);
    expect(find.byTooltip('Share weather card'), findsOneWidget);

    await tester.tap(find.byKey(ForecastShareAction.buttonKey));
    await tester.pumpAndSettle();

    expect(find.byType(WeatherSocialCard), findsOneWidget);
    expect(find.text('Portland, OR'), findsOneWidget);
    expect(find.text('12.34 WRF earned'), findsOneWidget);
    expect(find.text('Share weather card'), findsOneWidget);
  });

  testWidgets('sharing from the sheet invokes the existing capture flow', (
    tester,
  ) async {
    final launchedFiles = <List<XFile>>[];
    String? launchedText;
    final service = WeatherSocialCardShareService(
      captureCard: (_) async => Uint8List.fromList([9, 8, 7]),
      shareLauncher: (files, {text}) async {
        launchedFiles.add(files);
        launchedText = text;
      },
    );

    await usePhoneViewport(tester);
    await tester.pumpWidget(
      _host(
        ForecastShareAction(forecast: _sampleForecast(), shareService: service),
      ),
    );
    await tester.tap(find.byKey(ForecastShareAction.buttonKey));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Share weather card'));
    await tester.tap(find.text('Share weather card'));
    await tester.pumpAndSettle();

    expect(launchedFiles, hasLength(1));
    expect(launchedText, contains('Portland, OR'));
    expect(launchedText, contains('12.34 WRF'));
    expect(await launchedFiles.single.single.readAsBytes(), [9, 8, 7]);
  });
}
