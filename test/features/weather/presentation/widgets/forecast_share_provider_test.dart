import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/analytics/data/analytics_calculations.dart';
import 'package:wrfcoin_mobile/features/analytics/data/analytics_models.dart';
import 'package:wrfcoin_mobile/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';
import 'package:wrfcoin_mobile/features/social/weather_social_card.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/forecast_share_action.dart';

const _forecast = ForecastModel(
  temperature: 20,
  location: 'Synthetic cell',
  timestamp: '2026-09-29T12:00:00Z',
);

AnalyticsSnapshot snapshot(bool available, double amount) =>
    buildAnalyticsSnapshot(
      readings: const [],
      validationEvents: [
        CollectorValidationEvent(
          timestamp: DateTime.utc(2026, 9, 29),
          code: 'sync_accepted',
          message: 'accepted=5',
        ),
      ],
      syncedSubmissionCount: 5,
      earnedRewardWrf: amount,
      rewardTotalsAvailable: available,
    );

void main() {
  for (final available in [false, true]) {
    for (final amount in [0.0, 12.34]) {
      test(
        'actual share provider: available=$available amount=$amount',
        () async {
          final analytics = snapshot(available, amount);
          expect(analytics.summary.earnedWrf, amount);
          final container = ProviderContainer(
            overrides: [
              analyticsSnapshotProvider.overrideWith((ref) async => analytics),
            ],
          );
          addTearDown(container.dispose);
          // The share provider body is real; only its upstream snapshot is supplied.
          final rewards = await container.read(
            forecastShareRewardsProvider.future,
          );
          expect(rewards, available ? amount.toStringAsFixed(2) : isNull);
          final caption = WeatherSocialCardShareService.buildShareText(
            forecast: _forecast,
            weatherRewards: rewards,
          );
          expect(
            caption,
            contains(
              available ? '${amount.toStringAsFixed(2)} WRF' : 'Not available',
            ),
          );
        },
      );
    }
  }

  testWidgets(
    'actual provider hides an unconfirmed zero in surface and shared caption',
    (tester) async {
      String? caption;
      final service = WeatherSocialCardShareService(
        captureCard: (_) async {
          expect(find.text('Not available'), findsOneWidget);
          return Uint8List.fromList([1, 2, 3]);
        },
        shareLauncher: (_, {text}) async => caption = text,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsSnapshotProvider.overrideWith(
              (ref) async => snapshot(false, 0),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  ForecastShareAction(
                    forecast: _forecast,
                    shareService: service,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(ForecastShareAction.buttonKey));
      await tester.pumpAndSettle();
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('0.00 WRF earned'), findsNothing);
      await tester.ensureVisible(find.text('Share weather card'));
      await tester.tap(find.text('Share weather card'));
      await tester.pumpAndSettle();
      expect(caption, contains('Not available'));
      expect(caption, isNot(contains('0.00')));
    },
  );
}
