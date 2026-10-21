import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wrfcoin_mobile/features/social/weather_social_card.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';

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

void main() {
  group('WeatherSocialCardShareService', () {
    test('exports PNG bytes through the share pipeline', () async {
      final launchedFiles = <List<XFile>>[];
      String? launchedText;

      final service = WeatherSocialCardShareService(
        captureCard: (_) async => Uint8List.fromList([1, 2, 3, 4]),
        shareLauncher: (files, {text}) async {
          launchedFiles.add(files);
          launchedText = text;
        },
      );

      await service.shareCard(repaintKey: GlobalKey(), text: 'Hello WRFCoin');

      expect(launchedFiles, hasLength(1));
      expect(launchedText, 'Hello WRFCoin');
      expect(await launchedFiles.single.single.readAsBytes(), [1, 2, 3, 4]);
    });
  });

  group('WeatherSocialCard', () {
    testWidgets('renders weather and earnings details', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeatherSocialCard(
              forecast: _sampleForecast(),
              weatherRewards: '12.34',
              shareService: WeatherSocialCardShareService(
                captureCard: (_) async => Uint8List.fromList([1, 2, 3]),
                shareLauncher: (_, {text}) async {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('WRFCoin Social Weather'), findsOneWidget);
      expect(find.text('Portland, OR'), findsOneWidget);
      expect(find.text('23.4°C'), findsOneWidget);
      expect(find.text('12.34 WRF earned'), findsOneWidget);
      expect(find.text('Share weather card'), findsOneWidget);
    });

    testWidgets('share button exports PNG and opens the share launcher', (
      tester,
    ) async {
      final launchedFiles = <List<XFile>>[];
      String? launchedText;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeatherSocialCard(
              forecast: _sampleForecast(),
              weatherRewards: '12.34',
              shareService: WeatherSocialCardShareService(
                captureCard: (_) async => Uint8List.fromList([1, 2, 3, 4]),
                shareLauncher: (files, {text}) async {
                  launchedFiles.add(files);
                  launchedText = text;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Share weather card'));
      await tester.pump();

      expect(launchedFiles, hasLength(1));
      expect(launchedText, contains('Portland, OR'));
      expect(launchedText, contains('12.34 WRF'));

      final sharedFile = launchedFiles.single.single;
      expect(await sharedFile.readAsBytes(), [1, 2, 3, 4]);
    });

    test('buildShareText summarizes current weather and earnings', () {
      final text = WeatherSocialCardShareService.buildShareText(
        forecast: _sampleForecast(),
        weatherRewards: '12.34',
      );

      expect(text, contains('Portland, OR'));
      expect(text, contains('23.4°C'));
      expect(text, contains('12.34 WRF'));
    });
  });
}
