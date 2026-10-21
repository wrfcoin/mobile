import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/widgets/data/widget_snapshot_store.dart';

void main() {
  test(
    'snapshot preserves pending state without inventing an unavailable reward',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = WidgetSnapshotStore();

      await store.write(
        reading: SensorReadingModel(
          latitude: 1,
          longitude: 2,
          pressureHpa: 1009.5,
          timestamp: DateTime.utc(2026, 7, 29),
        ),
        pendingSyncCount: 2,
        lastSubmissionStatus: 'queued',
        rewardTotalsAvailable: false,
        earnedRewardWrf: 45,
      );

      final snapshot = await store.read();
      expect(snapshot!['pressureHpa'], 1009.5);
      expect(snapshot['pendingSyncCount'], 2);
      expect(snapshot['rewardTotalsAvailable'], isFalse);
      expect(snapshot.containsKey('earnedRewardWrf'), isFalse);
    },
  );
}
