import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_earned_provider.dart';
import 'package:wrfcoin_mobile/features/social/weather_social_card.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/forecast_share_action.dart';

const _forecast = ForecastModel(
  temperature: 20,
  location: 'Synthetic cell',
  timestamp: '2026-09-29T12:00:00Z',
);

void main() {
  // Real public-balance shape: `earned` is base units with 8 decimals.
  for (final (earned, shown) in [
    (null, null),
    ('0', '0'),
    ('100000000', '1'),
    ('1234000000', '12.34'),
  ]) {
    test('share text from wallet earned=$earned', () async {
      final container = ProviderContainer(
        overrides: [
          walletEarnedWrfProvider.overrideWith(
            (ref) async => walletEarnedWrfDisplay(
              WalletModel(
                address: 'wrf1wallet',
                balance: '0',
                earnedBalanceTotal: earned,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      // The share provider body is real; only the wallet read is supplied.
      final rewards = await container.read(forecastShareRewardsProvider.future);
      expect(rewards, shown);
      final caption = WeatherSocialCardShareService.buildShareText(
        forecast: _forecast,
        weatherRewards: rewards,
      );
      expect(caption, contains(shown == null ? 'Not available' : '$shown WRF'));
      expect(caption, isNot(contains('100000000')));
    });
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
            walletEarnedWrfProvider.overrideWith((ref) async => null),
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
