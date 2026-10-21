import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registration_service.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/fake_station_backend.dart';

class _Online implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _KeepOpenDb extends AppDatabase {
  _KeepOpenDb() : super(NativeDatabase.memory());
  @override
  Future<void> close() async {}
}

class _Wallet extends WalletSecureStorage {
  const _Wallet();
  @override
  Future<String?> getWalletAddress() async => syntheticAddress;
}

class _ThrowingRegistration extends StationRegistrationService {
  _ThrowingRegistration(ApiClient apiClient) : super(apiClient: apiClient);

  @override
  Future<StationRegistrationResult> register(
    StationSigningSession session, {
    required CollectKey collectKey,
    required double latitude,
    required double longitude,
  }) async => throw StateError('boom');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeStationBackend backend;
  late SyntheticSigner signer;
  late DateTime clock;
  late CollectKeyStore collectStore;

  SyncWorker worker({
    bool canSign = true,
    Future<StationSigningSession?> Function()? opener,
    CollectorRepository Function(AppDatabase)? repoFactory,
  }) => SyncWorker(
    connectivity: _Online(),
    walletSecureStorage: const _Wallet(),
    dbFactory: () => db,
    delay: (_) async {},
    now: () => clock,
    sessionOpener: canSign ? (opener ?? signer.open) : null,
    collectKeyStore: collectStore,
    canStartLogin: canSign,
    repositoryFactory: repoFactory ?? (database) {
      final apiClient = ApiClient(
        dio: backend.buildDio(),
        allowUnauthenticatedRequests: true,
      );
      return CollectorRepository(
        sensorDataSource: SensorDataSource(LocationService()),
        batteryMonitor: BatteryMonitor(),
        apiClient: apiClient,
        db: database,
        registration: StationRegistrationService(
          apiClient: apiClient,
          now: () => clock,
        ),
      );
    },
  );

  // Readings are ~30 minutes old at the test clock: inside the attester's
  // freshness window (SyncWorker.maxReadingAge).
  Future<void> seed(
    int n, {
    DateTime? at,
    double latitude = 37.7749,
    double longitude = -122.4194,
  }) async {
    for (var i = 0; i < n; i++) {
      await db.insertReading(
        SensorReadingsCompanion.insert(
          // Collect keeps 0.001 degree; only the registered cell is 0.1.
          latitude: latitude,
          longitude: longitude,
          pressureHpa: 1000.0 + i,
          timestamp: (at ?? DateTime.utc(2026, 9, 29, 11, 30)).add(
            Duration(minutes: i),
          ),
        ),
      );
    }
  }

  Future<String?> persistedStation() async =>
      (await SharedPreferences.getInstance()).getString(
        StationRegistrationService.registeredStationKey,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    collectStore = syntheticCollectStore();
    db = _KeepOpenDb();
    backend = FakeStationBackend();
    signer = SyntheticSigner();
    clock = DateTime.utc(2026, 9, 29, 12);
  });

  group('first foreground sync', () {
    test(
      'registers once at the 0.1 degree cell, then submits every reading',
      () async {
        await seed(3);

        final result = await worker().syncPendingReadings();

        expect(result.reason, SyncRunReason.success);
        expect(result.acceptedCount, 3);
        expect(result.pendingCount, 0);
        expect(backend.paths.take(2), [
          '/weather/stations/mobile/challenge',
          '/weather/stations/mobile',
        ]);
        expect(backend.registrations, 1);
        final register = backend.requests[1].body;
        expect(register['cell'], {'latE1': 378, 'lonE1': -1224});
        expect(register['deviceClass'], 'phone-barometer');
        expect(register['publicKey'], hasLength(64));
        expect(register['registrationSignature'], hasLength(128));
        expect(register['ownershipSignature'], hasLength(128));
        // The registration never carries the finer reading coordinates.
        final wire = jsonEncode(register);
        expect(wire, isNot(contains('37.77')));
        expect(wire, isNot(contains('122.41')));
        expect(register.containsKey('stationId'), isFalse);
        expect(
          await persistedStation(),
          StationRegistrationService.registrationMarker(
            syntheticStationId,
            (await collectStore.load(syntheticAddress))!.publicKeyHex,
          ),
        );
        expect(backend.count('/oracle/submit-data'), 3);
      },
    );

    test('a registered phone does not register again', () async {
      await seed(2);
      backend.registered = true;
      SharedPreferences.setMockInitialValues(
        await registeredPrefsFor(collectStore),
      );

      await worker().syncPendingReadings();

      expect(backend.count('/challenge'), 0);
      expect(backend.count('/weather/stations/mobile'), 0);
      expect(backend.count('/oracle/submit-data'), 2);
    });

    test(
      'idempotent: the backend already holds the station (reinstall)',
      () async {
        await seed(2);
        backend.registered = true; // server row exists, local flag does not

        final result = await worker().syncPendingReadings();

        expect(result.acceptedCount, 2);
        expect(
          backend.registrations,
          0,
          reason: 'server returned the existing row',
        );
        expect(backend.count('/weather/stations/mobile'), 1);
        expect(await persistedStation(), isNotNull);
      },
    );

    test(
      'a register response with a different station id is refused',
      () async {
        await seed(3);
        backend.registerResponseStationId = 'mob-${'0' * 32}';

        final result = await worker().syncPendingReadings();

        expect(result.reason, SyncRunReason.registrationRefused);
        expect(await persistedStation(), isNull);
        expect(backend.count('/oracle/submit-data'), 0);
        expect(backend.count('/prepare'), 0);
        expect(result.pendingCount, 3);
      },
    );

    test('a challenge naming another station is refused before signing or registering', () async {
      await seed(2);
      backend.challengeStationId = 'mob-${'1' * 32}';

      final result = await worker().syncPendingReadings();

      expect(result.reason, SyncRunReason.registrationRefused);
      expect(backend.count('/weather/stations/mobile'), 0);
      expect(result.pendingCount, 2);
    });

    test(
      'a server commitHash mismatch is refused and nothing is sent to submit',
      () async {
        await seed(3);
        backend.registered = true;
        backend.prepareCommitId = 'cd' * 32;

        final result = await worker().syncPendingReadings();

        expect(result.reason, SyncRunReason.commitRefused);
        expect(backend.count('/oracle/submit-data'), 0);
        expect(result.pendingCount, 3);
        expect(result.acceptedCount, 0);
      },
    );

    test('one biometric prompt (registration only) for a run of N readings', () async {
      await seed(7);

      final result = await worker().syncPendingReadings();

      expect(result.acceptedCount, 7);
      expect(signer.openAttempts, 1);
      expect(signer.sessionsOpened, 1);
      expect(backend.verifiedAuthSignatures, hasLength(7));
    });
  });

  group('never signs where it may not', () {
    test(
      'a background run leaves readings queued with an open-the-app state',
      () async {
        await seed(4);

        final result = await worker(canSign: false).syncPendingReadings();

        expect(backend.requests, isEmpty);
        expect(signer.openAttempts, 0);
        expect(result.reason, SyncRunReason.awaitingForeground);
        expect(result.pendingCount, 4);
        expect(result.message, contains('open the app'));
        expect(result.message, contains('4'));
        final metadata = await db.getSyncMetadata(sensorReadingsSyncTableName);
        expect(metadata?.lastSyncError, result.message);
      },
    );

    test(
      'a session opened while the app is not resumed behaves the same',
      () async {
        await seed(2);
        signer.foreground = false;

        final result = await worker().syncPendingReadings();

        expect(backend.requests, isEmpty);
        expect(result.reason, SyncRunReason.awaitingForeground);
        expect(result.pendingCount, 2);
      },
    );

    test(
      'a refused biometric prompt sends no request and keeps readings',
      () async {
        await seed(3);
        signer.biometricGranted = false;

        final result = await worker().syncPendingReadings();

        expect(backend.requests, isEmpty);
        expect(result.reason, SyncRunReason.signingRefused);
        expect(result.pendingCount, 3);
        expect(signer.openAttempts, 1, reason: 'no auto-loop on refusal');
      },
    );
  });

  group('STATION_NOT_OWNED after registration', () {
    test('re-registers once and ends the run; next run uploads', () async {
      await seed(3);
      SharedPreferences.setMockInitialValues(
        await registeredPrefsFor(collectStore),
      );
      backend.registered = false; // the server lost the row

      final result = await worker().syncPendingReadings();

      expect(result.reason, SyncRunReason.stationNotRegistered);
      expect(result.acceptedCount, 0);
      expect(result.pendingCount, 3);
      expect(backend.count('/prepare'), 1);
      final next = await worker().syncPendingReadings();
      expect(next.acceptedCount, 3);
      expect(backend.count('/weather/stations/mobile'), 1);
      expect(backend.registrations, 1);
    });

    test(
      'STATION_NOT_OWNED stops after one re-registration even if rejection persists',
      () async {
        await seed(3);
        SharedPreferences.setMockInitialValues(
          await registeredPrefsFor(collectStore),
        );
        backend.stickyNotOwned = true;

        final result = await worker().syncPendingReadings();

        expect(result.reason, SyncRunReason.stationNotRegistered);
        expect(backend.count('/weather/stations/mobile'), 1);
        expect(backend.count('/prepare'), 1);
        expect(result.pendingCount, 3);
        // A second run gets its own single re-registration, not a loop.
        expect(signer.openAttempts, 1);
      },
    );
  });

  group('stale readings (design Q8)', () {
    // The oracle attester refuses readings older than 3600 s
    // (core4 shared-protocol oracle/mechanical.rs:53,223); the worker cuts
    // off at SyncWorker.maxReadingAge (50 min) so none is signed for nothing.
    test('the cutoff leaves ten minutes under the attester hour', () {
      expect(SyncWorker.maxReadingAge, const Duration(minutes: 50));
    });

    test('drops readings past the cutoff with a one-time notice', () async {
      await seed(2, at: clock.subtract(const Duration(minutes: 55)));
      await seed(2);
      backend.registered = true;

      final first = await worker().syncPendingReadings();

      expect(first.droppedStaleCount, 2);
      expect(first.notice, contains('2'));
      expect(first.acceptedCount, 2);
      expect(first.pendingCount, 0);
      expect(
        backend.count('/oracle/submit-data'),
        2,
        reason: 'a dropped reading is neither prepared nor signed',
      );
      expect(backend.count('/prepare'), 2);

      await seed(1);
      final second = await worker().syncPendingReadings();
      expect(second.droppedStaleCount, 0);
      expect(second.notice, isNull);
    });

    test('a reading 49 minutes old is still submitted', () async {
      await seed(1, at: clock.subtract(const Duration(minutes: 49)));
      backend.registered = true;

      final result = await worker().syncPendingReadings();

      expect(result.droppedStaleCount, 0);
      expect(result.acceptedCount, 1);
    });

    test('a reading 51 minutes old is dropped, never signed', () async {
      await seed(1, at: clock.subtract(const Duration(minutes: 51)));
      backend.registered = true;

      final result = await worker().syncPendingReadings();

      expect(result.droppedStaleCount, 1);
      expect(result.acceptedCount, 0);
      expect(backend.requests, isEmpty);
    });
  });

  group('submission order and registration cell', () {
    Future<void> insertAt(DateTime t, double lat, double lon) => db.insertReading(
      SensorReadingsCompanion.insert(
        latitude: lat,
        longitude: lon,
        pressureHpa: 1000,
        timestamp: t,
      ),
    );

    test('readings are sent oldest first, whatever the insert order', () async {
      backend.registered = true;
      final base = DateTime.utc(2026, 9, 29, 11, 30);
      // Newest inserted first.
      for (final m in [5, 3, 4, 1, 2]) {
        await insertAt(base.add(Duration(minutes: m)), 37.7749, -122.4194);
      }

      await worker().syncPendingReadings();

      final sent = [
        for (final r in backend.requests)
          if (r.path == '/oracle/submit-data/prepare')
            DateTime.parse(r.body['timestamp'] as String),
      ];
      expect(sent, hasLength(5));
      expect(sent, [...sent]..sort());
    });

    test('registers at the cell of the most recent reading', () async {
      // The oldest fix is somewhere else entirely (0.1 deg cells 400/-1000).
      await insertAt(DateTime.utc(2026, 9, 29, 11, 20), 40.04, -100.04);
      await insertAt(DateTime.utc(2026, 9, 29, 11, 50), 37.7749, -122.4194);
      await insertAt(DateTime.utc(2026, 9, 29, 11, 30), 41.04, -101.04);

      await worker().syncPendingReadings();

      final register = backend.requests
          .firstWhere((r) => r.path == '/weather/stations/mobile')
          .body;
      expect(register['cell'], {'latE1': 378, 'lonE1': -1224});
    });
  });

  group('the signing session', () {
    test('a background worker ignores any opener it is handed', () async {
      await seed(3);

      final result = await SyncWorker(
        connectivity: _Online(),
        walletSecureStorage: const _Wallet(),
        dbFactory: () => db,
        now: () => clock,
        canStartLogin: false,
        sessionOpener: signer.open,
      ).syncPendingReadings();

      expect(signer.openAttempts, 0, reason: 'the key was never read');
      expect(signer.sessionsOpened, 0);
      expect(backend.requests, isEmpty);
      expect(result.reason, SyncRunReason.awaitingForeground);
      expect(result.pendingCount, 3);
    });

    Future<bool> isClosed(StationSigningSession s) async {
      try {
        await s.signOwnership();
        return false;
      } on StateError {
        return true;
      }
    }

    test('closed after a successful run', () async {
      await seed(2);
      backend.registered = true;
      StationSigningSession? opened;
      final result = await worker(
        opener: () async => opened = await signer.open(),
      ).syncPendingReadings();

      expect(result.reason, SyncRunReason.success);
      expect(await isClosed(opened!), isTrue);
    });

    test('closed after a commit refusal', () async {
      await seed(2);
      backend.registered = true;
      backend.prepareCommitId = 'cd' * 32;
      StationSigningSession? opened;
      final result = await worker(
        opener: () async => opened = await signer.open(),
      ).syncPendingReadings();

      expect(result.reason, SyncRunReason.commitRefused);
      expect(await isClosed(opened!), isTrue);
    });

    test('closed when the registration throws', () async {
      await seed(2);
      StationSigningSession? opened;

      await expectLater(
        worker(
          opener: () async => opened = await signer.open(),
          repoFactory: (database) {
            final apiClient = ApiClient(
              dio: backend.buildDio(),
              allowUnauthenticatedRequests: true,
            );
            return CollectorRepository(
              sensorDataSource: SensorDataSource(LocationService()),
              batteryMonitor: BatteryMonitor(),
              apiClient: apiClient,
              db: database,
              registration: _ThrowingRegistration(apiClient),
            );
          },
        ).syncPendingReadings(),
        throwsStateError,
      );

      expect(opened, isNotNull);
      expect(await isClosed(opened!), isTrue);
    });
  });

  group('registration challenge checks', () {
    test('a challenge for another chain is refused before signing', () async {
      await seed(2);
      backend.challengeChainId = '1';

      final result = await worker().syncPendingReadings();

      expect(result.reason, SyncRunReason.registrationRefused);
      expect(backend.count('/weather/stations/mobile'), 0);
      expect(result.pendingCount, 2);
    });

    test('a challenge living longer than 10 minutes is refused', () async {
      await seed(2);
      backend.challengeExpiresIn =
          StationRegistrationService.maxChallengeLifetime.inSeconds + 1;

      final result = await worker().syncPendingReadings();

      expect(result.reason, SyncRunReason.registrationRefused);
      expect(backend.count('/weather/stations/mobile'), 0);
    });

    test('a challenge of exactly 10 minutes is accepted', () async {
      await seed(2);
      backend.challengeExpiresIn =
          StationRegistrationService.maxChallengeLifetime.inSeconds;

      final result = await worker().syncPendingReadings();

      expect(result.reason, SyncRunReason.success);
    });
  });
}
