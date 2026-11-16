import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CollectorPreferences', () {
    late CollectorPreferences preferences;

    setUp(() {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      preferences = const CollectorPreferences();
    });

    test('persists collector sync snapshot fields across reloads', () async {
      await preferences.save(
        const CollectorPreferencesState(
          isCollecting: true,
          intervalMinutes: 20,
          batteryThreshold: 12,
          syncedSubmissionCount: 7,
          lastSubmissionId: 'submission-123',
          lastCommitId: 'c0ffee000000000000000000000000000000000000000000000000004d2a91e7',
          lastSubmissionStatus: 'pending',
        ),
      );

      final restored = await preferences.load();

      expect(restored.isCollecting, isTrue);
      expect(restored.intervalMinutes, 20);
      expect(restored.batteryThreshold, 12);
      expect(restored.syncedSubmissionCount, 7);
      expect(restored.lastSubmissionId, 'submission-123');
      expect(
        restored.lastCommitId,
        'c0ffee000000000000000000000000000000000000000000000000004d2a91e7',
      );
      expect(restored.lastSubmissionStatus, 'pending');
    });

    test(
      'drops the old summed "WRF settled" figure on the next save',
      () async {
        // Older builds saved the sum of submit answers (each the lifetime
        // total in base units) as WRF. It is never read back and is removed.
        SharedPreferences.setMockInitialValues(const <String, Object>{
          'collector.rewardTotalsAvailable': true,
          'collector.earnedRewardWrf': 300000000.0,
        });
        final restored = await preferences.load();
        await preferences.save(restored);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('collector.rewardTotalsAvailable'), isFalse);
        expect(prefs.containsKey('collector.earnedRewardWrf'), isFalse);
      },
    );

    test('appends and clears validation events', () async {
      await preferences.appendValidationEvent(
        CollectorValidationEvent(
          timestamp: DateTime(2026, 3, 10, 9, 0),
          code: 'collect_success',
          message: 'Captured 1012.0 hPa.',
        ),
      );
      await preferences.appendValidationEvent(
        CollectorValidationEvent(
          timestamp: DateTime(2026, 3, 10, 9, 5),
          code: 'offline',
          message: 'accepted=0, failed=0, pending=1',
        ),
      );

      final events = await preferences.loadValidationEvents();

      expect(events, hasLength(2));
      expect(events.first.code, 'offline');
      expect(events.last.code, 'collect_success');

      await preferences.clearValidationEvents();
      expect(await preferences.loadValidationEvents(), isEmpty);
    });
  });
}
