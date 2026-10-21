import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/forecast_detail_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_detail_screen.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/forecast_share_action.dart';

/// Keeps the screen in its loading state without touching the network.
class _StaticDetailNotifier extends ForecastDetailNotifier {
  @override
  ForecastDetailState build() => const ForecastDetailState(loading: true);

  @override
  Future<void> loadLocal() async {}
}

/// Default preferences without reading SharedPreferences.
class _StaticPreferencesNotifier extends AppPreferencesNotifier {
  @override
  AppPreferencesState build() => const AppPreferencesState();
}

Widget _screen(ForecastModel? forecast) {
  return ProviderScope(
    overrides: [
      forecastDetailProvider.overrideWith(_StaticDetailNotifier.new),
      appPreferencesProvider.overrideWith(_StaticPreferencesNotifier.new),
      forecastShareRewardsProvider.overrideWith((ref) async => '0.50'),
    ],
    child: MaterialApp(home: ForecastDetailScreen(currentForecast: forecast)),
  );
}

void main() {
  // The loading-state shimmer list needs a phone-sized viewport; the default
  // test surface is too short for it and overflows.
  Future<void> usePhoneViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  const forecast = ForecastModel(
    temperature: 18.0,
    humidity: 70,
    pressure: 1009.0,
    windSpeed: 2.0,
    windDirection: 'S',
    precipitation: 0.0,
    location: 'Duluth, MN',
    timestamp: '2026-09-16T12:00:00Z',
  );

  testWidgets(
    'forecast-detail app bar exposes the share action when a forecast is present',
    (tester) async {
      await usePhoneViewport(tester);
      await tester.pumpWidget(_screen(forecast));
      await tester.pump();

      expect(find.byKey(ForecastShareAction.buttonKey), findsOneWidget);
    },
  );

  testWidgets('no share action without a forecast to share', (tester) async {
    await usePhoneViewport(tester);
    await tester.pumpWidget(_screen(null));
    await tester.pump();

    expect(find.byKey(ForecastShareAction.buttonKey), findsNothing);
  });
}
