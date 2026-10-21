import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/social/weather_social_card.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/forecast_share_action.dart';

const _forecast = ForecastModel(
  temperature: 20,
  location: 'Synthetic test cell',
  timestamp: '2026-09-29T12:00:00Z',
);

void main() {
  Future<void> open(
    WidgetTester tester,
    AsyncValue<String> state, {
    WeatherSocialCardShareService? service,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [forecastShareRewardsProvider.overrideWithValue(state)],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ForecastShareAction(forecast: _forecast, shareService: service),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(ForecastShareAction.buttonKey));
    await tester.pumpAndSettle();
  }

  final unavailableStates = <String, AsyncValue<String>>{
    'loading': const AsyncLoading<String>(),
    'error': AsyncError<String>(
      StateError('synthetic analytics failure'),
      StackTrace.empty,
    ),
  };
  for (final entry in unavailableStates.entries) {
    testWidgets(
      '${entry.key}: surface and exported caption report unavailable',
      (tester) async {
        String? caption;
        var captures = 0;
        final service = WeatherSocialCardShareService(
          captureCard: (key) async {
            expect(key.currentContext, isNotNull);
            expect(find.text('Not available'), findsOneWidget);
            captures++;
            return Uint8List.fromList([1, 2, 3]);
          },
          shareLauncher: (_, {text}) async {
            caption = text;
          },
        );
        await open(tester, entry.value, service: service);
        expect(find.text('Not available'), findsOneWidget);
        expect(find.text('0.00 WRF earned'), findsNothing);
        expect(find.text('12.34 WRF earned'), findsNothing);
        await tester.ensureVisible(find.text('Share weather card'));
        await tester.tap(find.text('Share weather card'));
        await tester.pumpAndSettle();
        expect(captures, 1);
        expect(caption, contains('Not available'));
        expect(caption, isNot(contains('0.00')));
        expect(caption, isNot(contains('null')));
      },
    );
  }

  for (final amount in ['0.00', '12.34']) {
    testWidgets('reported $amount stays real on card and caption', (
      tester,
    ) async {
      String? caption;
      final service = WeatherSocialCardShareService(
        captureCard: (_) async => Uint8List.fromList([1, 2, 3]),
        shareLauncher: (_, {text}) async {
          caption = text;
        },
      );
      await open(tester, AsyncData<String>(amount), service: service);
      expect(find.text('$amount WRF earned'), findsOneWidget);
      expect(find.text('Not available'), findsNothing);
      await tester.ensureVisible(find.text('Share weather card'));
      await tester.tap(find.text('Share weather card'));
      await tester.pumpAndSettle();
      expect(caption, contains('$amount WRF'));
      expect(caption, isNot(contains('Not available')));
    });
  }

  testWidgets('refresh hides the previous reward while awaiting confirmation', (
    tester,
  ) async {
    final pending = Completer<String>();
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        forecastShareRewardsProvider.overrideWith(
          (ref) => calls++ == 0 ? Future.value('12.34') : pending.future,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: [ForecastShareAction(forecast: _forecast)]),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(ForecastShareAction.buttonKey));
    await tester.pumpAndSettle();
    expect(find.text('12.34 WRF earned'), findsOneWidget);
    final refresh = container.refresh(forecastShareRewardsProvider.future);
    await tester.pumpAndSettle();
    try {
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('12.34 WRF earned'), findsNothing);
    } finally {
      pending.complete('0.00');
      await refresh;
      await tester.pumpAndSettle();
    }
    expect(find.text('0.00 WRF earned'), findsOneWidget);
  });

  testWidgets(
    'unresolved provider changes from unavailable to a reported zero',
    (tester) async {
      final pending = Completer<String>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forecastShareRewardsProvider.overrideWith((ref) => pending.future),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [ForecastShareAction(forecast: _forecast)],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(ForecastShareAction.buttonKey));
      await tester.pumpAndSettle();
      try {
        expect(find.text('Not available'), findsOneWidget);
      } finally {
        pending.complete('0.00');
        await tester.pumpAndSettle();
      }
      expect(find.text('0.00 WRF earned'), findsOneWidget);
      expect(find.text('Not available'), findsNothing);
    },
  );
}
