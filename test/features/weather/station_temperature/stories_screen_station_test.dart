import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/station_temperature_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/weather_stories_screen.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/station_temperature.dart';

class _NoLocalHistory implements WeatherHistoryRepository {
  @override
  Future<List<SensorSnapshot>> loadHistory() async => const [];
}

class _Fixed extends StationTemperatureNotifier {
  _Fixed(this._s);
  final StationTemperatureState _s;
  @override
  StationTemperatureState build() => _s;
}

Future<void> _pump(WidgetTester tester, StationTemperatureState s) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weatherHistoryRepositoryProvider.overrideWithValue(_NoLocalHistory()),
        stationTemperatureProvider.overrideWith(() => _Fixed(s)),
      ],
      child: const MaterialApp(home: WeatherStoriesScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('no local stories and station data hidden: the normal empty view', (tester) async {
    await _pump(tester, const StationTemperatureState());
    expect(find.text('No stories yet'), findsOneWidget);
    expect(find.text('Nearby station temperatures'), findsNothing);
  });

  testWidgets('no local stories but station narratives: they are shown, not the empty view', (tester) async {
    final narratives = buildStationTemperatureNarratives(
      StationTemperatureHistory.fromJson({
        'daily': [
          {'date': '2026-09-29', 'minC': 10, 'maxC': 16, 'meanC': 12.0, 'samples': 4},
          {'date': '2026-09-30', 'minC': 12, 'maxC': 19, 'meanC': 14.0, 'samples': 4},
        ],
      }),
      DateTime.utc(2026, 10, 1, 15),
    );
    await _pump(tester, StationTemperatureState(status: StationTemperatureStatus.ready, narratives: narratives));
    expect(find.text('No stories yet'), findsNothing);
    expect(find.text('Nearby station temperatures'), findsOneWidget);
    expect(find.text('Yesterday was warmer than the day before by 2.0°C'), findsOneWidget);
  });

  testWidgets('station data empty: an honest no-data line inside the stories page', (tester) async {
    await _pump(tester, const StationTemperatureState(status: StationTemperatureStatus.empty));
    expect(find.textContaining('No recent station temperature data'), findsOneWidget);
  });
}
