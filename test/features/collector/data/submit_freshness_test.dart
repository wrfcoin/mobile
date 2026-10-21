import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fake_station_backend.dart';
import '../../../test_helpers/fakes.dart';

class _Signer implements CommitSigner {
  _Signer(this.key, this.afterSigning);
  final CollectKey key;
  final void Function() afterSigning;
  int signatures = 0;
  @override
  String get stationId => key.stationId;
  @override
  String get publicKeyHex => key.publicKeyHex;
  @override
  Future<SignedStationMessage> signCommitAuthorization({
    required String commitId,
  }) async {
    final message = await key.signCommitAuthorization(commitId: commitId);
    signatures++;
    afterSigning();
    return message;
  }
}

class _Backend extends FakeStationBackend {
  _Backend(this.afterPrepare);
  final void Function() afterPrepare;
  @override
  Future<Response<dynamic>> handle(RequestOptions options) async {
    final response = await super.handle(options);
    if (options.path.endsWith('/prepare')) afterPrepare();
    return response;
  }
}

void main() {
  for (final (stage, crossingHour) in [
    ('before prepare', false),
    ('during prepare', false),
    ('during signing', false),
    ('before prepare', true),
    ('during prepare', true),
    ('during signing', true),
  ]) {
    test(
      'expiry $stage ${crossingHour ? 'past3600s' : 'past3000s'} sends no submit and claims no reward',
      () async {
        var clock = DateTime.utc(2026, 9, 29, 12);
        final captured = clock.subtract(
          Duration(
            seconds: stage == 'before prepare'
                ? (crossingHour ? 3601 : 3060)
                : 2940,
          ),
        );
        final backend = _Backend(() {
          if (stage == 'during prepare') {
            clock = clock.add(Duration(seconds: crossingHour ? 661 : 120));
          }
        })..registered = true;
        final store = FakeCollectorLocalStore()..pendingCount = 1;
        final signer = _Signer(await syntheticCollectKey(), () {
          if (stage == 'during signing') {
            clock = clock.add(Duration(seconds: crossingHour ? 661 : 120));
          }
        });
        final repo = CollectorRepository(
          sensorDataSource: SensorDataSource(LocationService()),
          batteryMonitor: BatteryMonitor(),
          apiClient: ApiClient(
            dio: backend.buildDio(),
            allowUnauthenticatedRequests: true,
          ),
          db: store,
        );
        final result = await repo.submitBatch(
          [
            SensorReading(
              id: 1,
              latitude: 10.1,
              longitude: 20.2,
              pressureHpa: 1013.25,
              timestamp: captured,
              synced: false,
            ),
          ],
          walletAddress: syntheticAddress,
          signer: signer,
          isReadingFresh: (r) => !r.timestamp.isBefore(
            clock.subtract(const Duration(minutes: 50)),
          ),
        );
        expect(backend.count('/prepare'), stage == 'before prepare' ? 0 : 1);
        expect(signer.signatures, stage == 'during signing' ? 1 : 0);
        expect(backend.count('/oracle/submit-data'), 0);
        expect(store.syncedIds, isEmpty);
        expect(result.acceptedCount, 0);
        expect(result.failedCount, 0);
        expect(result.expiredCount, 1);
        expect(result.rewardTotalsAvailable, isFalse);
        expect(result.rewardWrfTotal, 0);
      },
    );
  }
}
