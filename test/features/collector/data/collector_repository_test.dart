import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_helpers/fake_station_backend.dart';

import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fakes.dart';

void main() {
  group('CollectorRepository.submitBatch', () {
    late FakeCollectorLocalStore store;
    late CollectKey session;

    setUp(() async {
      store = FakeCollectorLocalStore();
      session = await syntheticCollectKey();
    });

    Future<CollectorRepository> buildRepository({
      required Future<Response<dynamic>> Function(
        RequestOptions options,
        int requestIndex,
      )
      handler,
    }) async {
      var requestIndex = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, interceptorHandler) async {
            final prepared = answerPrepare(options);
            if (prepared != null) {
              // The prepare leg is not what these tests count.
              interceptorHandler.resolve(prepared);
              return;
            }
            requestIndex++;
            try {
              interceptorHandler.resolve(await handler(options, requestIndex));
            } on DioException catch (error) {
              interceptorHandler.reject(error);
            }
          },
        ),
      );

      return CollectorRepository(
        sensorDataSource: SensorDataSource(LocationService()),
        batteryMonitor: BatteryMonitor(),
        apiClient: ApiClient(dio: dio, allowUnauthenticatedRequests: true),
        db: store,
      );
    }

    List<SensorReading> seedReadings(int count) {
      store.pendingCount = count;
      return List<SensorReading>.generate(
        count,
        (index) => SensorReading(
          id: index + 1,
          latitude: 37.77 + index,
          longitude: -122.41 - index,
          pressureHpa: 1000.0 + index,
          timestamp: DateTime(2026, 3, 10, 12, index),
          synced: false,
        ),
      );
    }

    test('returns zero counts for an empty batch', () async {
      final repository = await buildRepository(
        handler: (options, requestIndex) async => Response(
          requestOptions: options,
          data: const <String, dynamic>{'success': true},
        ),
      );

      final result = await repository.submitBatch(
        const <SensorReading>[],
        walletAddress: 'wrf1wallet',
        signer: session,
      );

      expect(result.acceptedCount, 0);
      expect(result.failedCount, 0);
      expect(result.rewardWrfTotal, 0);
      expect(result.rewardTotalsAvailable, isFalse);
      expect(result.lastSubmissionId, isNull);
      expect(result.lastCommitId, isNull);
    });

    test('marks readings synced and captures submission metadata', () async {
      final repository = await buildRepository(
        handler: (options, requestIndex) async => Response(
          requestOptions: options,
          data: <String, dynamic>{
            'success': true,
            'submissionId': 'sub-$requestIndex',
            'status': 'pending',
          },
        ),
      );
      final readings = seedReadings(2);

      final result = await repository.submitBatch(
        readings,
        walletAddress: 'wrf1wallet',
        signer: session,
      );

      expect(result.acceptedCount, 2);
      expect(result.failedCount, 0);
      expect(result.lastSubmissionId, 'sub-2');
      // The phone's own commit id for the last accepted reading (proof card link).
      expect(result.lastCommitId, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(result.lastSubmissionStatus, 'pending');
      expect(result.rewardTotalsAvailable, isFalse);
      expect(store.syncedIds, [1, 2]);
      expect(await store.getPendingSyncCount(), 0);
    });

    test('parses direct reward fields when backend provides them', () async {
      final repository = await buildRepository(
        handler: (options, requestIndex) async => Response(
          requestOptions: options,
          data: <String, dynamic>{
            'success': true,
            'submissionId': 'sub-$requestIndex',
            'status': 'accepted',
            'rewardAmount': '1.25',
          },
        ),
      );

      final result = await repository.submitBatch(
        seedReadings(2),
        walletAddress: 'wrf1wallet',
        signer: session,
      );

      expect(result.acceptedCount, 2);
      expect(result.rewardTotalsAvailable, isTrue);
      expect(result.rewardWrfTotal, closeTo(2.5, 0.0001));
    });

    test('parses nested reward totals without inventing zeros', () async {
      final repository = await buildRepository(
        handler: (options, requestIndex) async => Response(
          requestOptions: options,
          data: <String, dynamic>{
            'success': true,
            'submissionId': 'sub-$requestIndex',
            'status': 'accepted',
            'rewards': <String, dynamic>{'totalAmount': 0.5},
          },
        ),
      );

      final result = await repository.submitBatch(
        seedReadings(2),
        walletAddress: 'wrf1wallet',
        signer: session,
      );

      expect(result.rewardTotalsAvailable, isTrue);
      expect(result.rewardWrfTotal, closeTo(1.0, 0.0001));
    });

    test('keeps rejected or failed readings unsynced', () async {
      final repository = await buildRepository(
        handler: (options, requestIndex) async {
          if (requestIndex == 1) {
            return Response(
              requestOptions: options,
              data: const <String, dynamic>{'accepted': false},
            );
          }

          throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline',
          );
        },
      );

      final result = await repository.submitBatch(
        seedReadings(2),
        walletAddress: 'wrf1wallet',
        signer: session,
      );

      expect(result.acceptedCount, 0);
      expect(result.failedCount, 2);
      expect(await store.getPendingSyncCount(), 2);
      expect(store.syncedIds, isEmpty);
      expect(result.errorMessage, contains('offline'));
    });

    test(
      'requires an authenticated API client before syncing reward readings',
      () async {
        final dio = Dio();
        var requestCount = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestCount++;
              handler.resolve(Response(requestOptions: options));
            },
          ),
        );

        final repository = CollectorRepository(
          sensorDataSource: SensorDataSource(LocationService()),
          batteryMonitor: BatteryMonitor(),
          apiClient: ApiClient(dio: dio),
          db: store,
        );

        final result = await repository.submitBatch(
          seedReadings(1),
          walletAddress: '0x7e5f4552091a69125d5dfcb7b8c2659029395bdf',
          signer: session,
        );

        expect(result.acceptedCount, 0);
        expect(result.failedCount, 1);
        expect(result.errorMessage, contains('Wallet authentication required'));
        expect(requestCount, 0);
        expect(store.syncedIds, isEmpty);
      },
    );

    test('parses reward from wrfEarned key', () async {
      final repository = await buildRepository(
        handler: (options, requestIndex) async => Response(
          requestOptions: options,
          data: <String, dynamic>{
            'success': true,
            'submissionId': 'sub-$requestIndex',
            'status': 'accepted',
            'wrfEarned': '0.75',
          },
        ),
      );

      final result = await repository.submitBatch(
        seedReadings(1),
        walletAddress: 'wrf1wallet',
        signer: session,
      );

      expect(result.rewardTotalsAvailable, isTrue);
      expect(result.rewardWrfTotal, closeTo(0.75, 0.0001));
    });

    test('parses reward from rewards.amount nested path', () async {
      final repository = await buildRepository(
        handler: (options, requestIndex) async => Response(
          requestOptions: options,
          data: <String, dynamic>{
            'success': true,
            'submissionId': 'sub-$requestIndex',
            'status': 'accepted',
            'rewards': <String, dynamic>{'amount': 0.33},
          },
        ),
      );

      final result = await repository.submitBatch(
        seedReadings(1),
        walletAddress: 'wrf1wallet',
        signer: session,
      );

      expect(result.rewardTotalsAvailable, isTrue);
      expect(result.rewardWrfTotal, closeTo(0.33, 0.0001));
    });

    test('accepts responses with accepted:true flag', () async {
      final repository = await buildRepository(
        handler: (options, requestIndex) async => Response(
          requestOptions: options,
          data: <String, dynamic>{
            'accepted': true,
            'submissionId': 'sub-$requestIndex',
            'status': 'confirmed',
          },
        ),
      );

      final result = await repository.submitBatch(
        seedReadings(2),
        walletAddress: 'wrf1wallet',
        signer: session,
      );

      expect(result.acceptedCount, 2);
      expect(result.failedCount, 0);
      expect(result.lastSubmissionStatus, 'confirmed');
    });
  });

  group('CollectorRepository.recommendedIntervalMinutes', () {
    test('doubles interval below 20% battery', () async {
      final lowBatteryRepo = CollectorRepository(
        sensorDataSource: SensorDataSource(LocationService()),
        batteryMonitor: FakeBatteryMonitor(batteryLevel: 15),
        apiClient: ApiClient(dio: Dio(), allowUnauthenticatedRequests: true),
        db: FakeCollectorLocalStore(),
      );

      expect(await lowBatteryRepo.recommendedIntervalMinutes(20), 40);
      // SamplingPolicy clamps to the 15-minute workmanager floor.
      expect(await lowBatteryRepo.recommendedIntervalMinutes(10), 20);

      final normalBatteryRepo = CollectorRepository(
        sensorDataSource: SensorDataSource(LocationService()),
        batteryMonitor: FakeBatteryMonitor(batteryLevel: 50),
        apiClient: ApiClient(dio: Dio()),
        db: FakeCollectorLocalStore(),
      );

      expect(await normalBatteryRepo.recommendedIntervalMinutes(20), 20);
      expect(await normalBatteryRepo.recommendedIntervalMinutes(10), 15);
    });
  });
}
