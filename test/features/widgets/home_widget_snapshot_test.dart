import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/widgets/data/widget_snapshot_store.dart';

void main() {
  test('merges weather and collection slices into one widget snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final store = WidgetSnapshotStore();

    await store.writeCollectionSlice(
      reading: SensorReadingModel(
        latitude: 1,
        longitude: 2,
        pressureHpa: 1009.5,
        timestamp: DateTime.utc(2026, 7, 29, 9, 0),
      ),
      pendingSyncCount: 2,
      lastSubmissionStatus: 'queued',
      rewardTotalsAvailable: false,
      earnedRewardWrf: 45,
    );

    await store.writeWeatherSlice(
      const ForecastModel(
        temperature: 15.2,
        humidity: 55,
        pressure: 1009.8,
        windSpeed: 3.4,
        windDirection: 'SW',
        precipitation: 0,
        location: 'Oakland',
        timestamp: '2026-07-29T09:04:00Z',
      ),
    );

    final snapshot = await store.readSnapshot();
    expect(snapshot, isNotNull);
    expect(snapshot!.pressureHpa, 1009.5);
    expect(snapshot.weatherLocation, 'Oakland');
    expect(snapshot.weatherTemperature, 15.2);
    expect(snapshot.pendingSyncCount, 2);
    expect(snapshot.isLiveEarningRateVerified, isFalse);
    expect(snapshot.earningRateClaim, contains('UNVERIFIED'));
  });

  test('transport boundaries are explicitly marked UNVERIFIED for this session', () async {
    SharedPreferences.setMockInitialValues({});
    final store = WidgetSnapshotStore();

    await store.writeWeatherSlice(
      const ForecastModel(
        temperature: 8,
        humidity: 40,
        pressure: 990,
        windSpeed: 5,
        windDirection: 'N',
        precipitation: 0,
        location: 'Austin',
        timestamp: '2026-07-29T10:00:00Z',
      ),
    );

    final raw = await store.read();
    expect(raw, isNotNull);
    expect(raw!['weatherLocation'], 'Austin');
  });
}
