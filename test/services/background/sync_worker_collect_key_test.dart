import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registration_service.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/fake_station_backend.dart';

// M3b (mobile#323, design §11): a separate, non-biometric COLLECT KEY signs
// commit authorizations in foreground AND Workmanager runs; the wallet key
// signs registration only. Synthetic keys only.

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

const _oldKey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeStationBackend backend;
  late SyntheticSigner signer;
  late CountingKeyValueStorage collectStorage;
  late CollectKeyStore collectStore;
  late DateTime clock;
  StationSigningSession? openedSession;

  SyncWorker worker({bool foreground = true}) => SyncWorker(
    connectivity: _Online(),
    walletSecureStorage: const _Wallet(),
    dbFactory: () => db,
    delay: (_) async {},
    now: () => clock,
    sessionOpener: foreground
        ? () async => openedSession = await signer.open()
        : null,
    collectKeyStore: collectStore,
    canStartLogin: foreground,
    repositoryFactory: (database) {
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

  Future<void> seed(int n) async {
    for (var i = 0; i < n; i++) {
      await db.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 37.7749,
          longitude: -122.4194,
          pressureHpa: 1000.0 + i,
          timestamp: DateTime.utc(
            2026,
            9,
            29,
            11,
            30,
          ).add(Duration(minutes: i)),
        ),
      );
    }
  }

  /// A phone that already completed a v2 registration with its collect key.
  Future<CollectKey> alreadyRegistered() async {
    SharedPreferences.setMockInitialValues(
      await registeredPrefsFor(collectStore),
    );
    final key = (await collectStore.load(syntheticAddress))!;
    backend.registered = true;
    backend.collectPubkey = key.publicKeyHex;
    return key;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = _KeepOpenDb();
    backend = FakeStationBackend();
    signer = SyntheticSigner();
    collectStorage = CountingKeyValueStorage();
    collectStore = syntheticCollectStore(storage: collectStorage);
    clock = DateTime.utc(2026, 9, 29, 12);
    openedSession = null;
  });

  group('the collect key', () {
    test('is generated once and reused', () async {
      await seed(2);

      final first = await worker().syncPendingReadings();
      final key = (await collectStore.load(syntheticAddress))!;
      await seed(2);
      final second = await worker().syncPendingReadings();

      expect(first.acceptedCount, 2);
      expect(second.acceptedCount, 2);
      expect(collectStorage.writes['collect_key_seed'], 1);
      expect(
        (await collectStore.load(syntheticAddress))!.publicKeyHex,
        key.publicKeyHex,
      );
      expect(backend.registrations, 1, reason: 'the second run just uploads');
      expect(backend.count('/weather/stations/mobile'), 1);
    });

    test('a different wallet never reuses another wallet\'s key', () async {
      final key = await collectStore.createFresh(syntheticAddress);
      expect(
        await collectStore.load('0x${'12' * 20}'),
        isNull,
        reason: 'bound to the wallet that authorised it',
      );
      expect(
        (await collectStore.load(syntheticAddress))!.publicKeyHex,
        key.publicKeyHex,
      );
    });

    test(
      'is stored outside the wallet namespace and needs no auth to read',
      () async {
        // The store touches nothing but its own two entries, and there is no
        // biometric collaborator anywhere in its API.
        await collectStore.createFresh(syntheticAddress);
        expect(collectStorage.writes.keys.toSet(), {
          'collect_key_seed',
          'collect_key_owner',
        });
        expect(signer.openAttempts, 0);
        final read = await collectStore.load(syntheticAddress);
        expect(read, isNotNull);
        expect(collectStorage.walletKeyReads, 0);
      },
    );

    test('the platform storage has its own namespace and no auth option', () {
      final source = File('lib/services/crypto/key_manager.dart')
          .readAsStringSync();
      final start = source.indexOf('const SecureKeyValueStorage.collectKey()');
      expect(start, greaterThan(0));
      final block = source.substring(start, source.indexOf(';', start));
      expect(block, contains("storageNamespace: 'wrfcoin_collect_key'"));
      // Keystore-backed with no user-authentication / biometric requirement.
      expect(block.toLowerCase(), isNot(contains('authenticat')));
      expect(block.toLowerCase(), isNot(contains('biometric')));
      expect(block.toLowerCase(), isNot(contains('userpresence')));
      expect(block.toLowerCase(), isNot(contains('accesscontrol')));
    });
  });

  group('registration v2', () {
    test(
      'registration marker binds the public key as well as the station',
      () async {
        final key = await alreadyRegistered();
        final apiClient = ApiClient(
          dio: backend.buildDio(),
          allowUnauthenticatedRequests: true,
        );
        final registration = StationRegistrationService(apiClient: apiClient);
        expect(
          await registration.isRegistered(syntheticStationId, key.publicKeyHex),
          isTrue,
        );
        expect(
          await registration.isRegistered(syntheticStationId, _oldKey),
          isFalse,
        );
      },
    );

    test(
      'prepare names the collect public key before any signature is made',
      () async {
        final key = await alreadyRegistered();
        await seed(1);
        final result = await worker(foreground: false).syncPendingReadings();
        expect(result.acceptedCount, 1);
        final prepare = backend.requests.firstWhere(
          (r) => r.path == '/oracle/submit-data/prepare',
        );
        expect(prepare.body['auth_pubkey'], key.publicKeyHex);
        expect(prepare.body, isNot(contains('auth_signature')));
      },
    );

    for (final failKey in ['collect_key_seed', 'collect_key_owner']) {
      test(
        'collect storage write failure at $failKey preserves readings and closes the wallet signer',
        () async {
          collectStore = syntheticCollectStore(
            storage: _FailingCollectStorage(failKey),
          );
          await seed(2);
          final result = await worker().syncPendingReadings();
          expect(result.reason, SyncRunReason.signingUnavailable);
          expect(result.acceptedCount, 0);
          expect(result.pendingCount, 2);
          expect(result.message, contains('Collect key storage'));
          expect(backend.requests, isEmpty);
          expect(signer.sessionsOpened, 1);
          expect(() => openedSession!.publicKeyHex, throwsStateError);
        },
      );
    }

    test(
      'the wallet signs A v2 naming the collect key, and it is sent',
      () async {
        await seed(1);

        await worker().syncPendingReadings();

        final key = (await collectStore.load(syntheticAddress))!;
        final register = backend.requests
            .firstWhere((r) => r.path == '/weather/stations/mobile')
            .body;
        expect(register['version'], 2);
        expect(register['collectPubkey'], key.publicKeyHex);
        expect(register['collectPubkey'], isNot(register['publicKey']));
        // The fake backend verifies preimage A v2 against the wallet key.
        expect(backend.verifiedRegistrationSignatures, hasLength(1));
        expect(register['registrationSignature'], hasLength(128));
        expect(register['ownershipSignature'], hasLength(128));
        expect(backend.collectPubkey, key.publicKeyHex);
        expect(await registeredMarker(), contains(key.publicKeyHex));
      },
    );

    test('the wallet key is opened once, for registration only', () async {
      await seed(5);

      final result = await worker().syncPendingReadings();

      expect(result.acceptedCount, 5);
      expect(signer.openAttempts, 1);
      expect(signer.storage.reads['wrf_private_key'], 1);
      expect(backend.verifiedAuthSignatures, hasLength(5));
    });
  });

  group('commit signing with the collect key', () {
    test('a Workmanager run signs with the collect key and uploads', () async {
      final key = await alreadyRegistered();
      await seed(3);

      final result = await worker(foreground: false).syncPendingReadings();

      expect(result.reason, SyncRunReason.success);
      expect(result.acceptedCount, 3);
      expect(result.pendingCount, 0);
      expect(backend.verifiedAuthSignatures, hasLength(3));
      final submits = backend.requests
          .where((r) => r.path == '/oracle/submit-data')
          .toList();
      expect(submits, hasLength(3));
      for (final r in submits) {
        expect(r.body['auth_pubkey'], key.publicKeyHex);
      }
      expect(signer.openAttempts, 0, reason: 'no wallet session in background');
      expect(backend.count('/weather/stations/mobile'), 0);
    });

    test('the wallet key is never read while signing commits', () async {
      await alreadyRegistered();
      await seed(4);

      final foreground = await worker().syncPendingReadings();
      await seed(4);
      final background = await worker(foreground: false).syncPendingReadings();

      expect(foreground.acceptedCount, 4);
      expect(background.acceptedCount, 4);
      expect(signer.openAttempts, 0);
      expect(signer.storage.walletKeyReads, 0);
      expect(collectStorage.walletKeyReads, 0);
      expect(backend.verifiedAuthSignatures, hasLength(8));
    });

    test(
      'readings older than 50 minutes are dropped in the background too',
      () async {
        await alreadyRegistered();
        await db.insertReading(
          SensorReadingsCompanion.insert(
            latitude: 1,
            longitude: 2,
            pressureHpa: 1000,
            timestamp: clock.subtract(const Duration(minutes: 55)),
          ),
        );
        await seed(1);

        final result = await worker(foreground: false).syncPendingReadings();

        expect(result.droppedStaleCount, 1);
        expect(result.acceptedCount, 1);
      },
    );
  });

  group('not registered yet needs the wallet and the foreground', () {
    test(
      'a background run waits: no request, no wallet, open-the-app',
      () async {
        await seed(3);

        final result = await worker(foreground: false).syncPendingReadings();

        expect(backend.requests, isEmpty);
        expect(signer.openAttempts, 0);
        expect(result.reason, SyncRunReason.awaitingForeground);
        expect(result.pendingCount, 3);
        expect(result.message, contains('open the app'));
        expect(result.message, contains('register'));
      },
    );

    test('M3 install (v1 marker, no collect key) re-registers as v2 on the '
        'next foreground sync', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mobile_station_registered_id': syntheticStationId,
      });
      backend.registered = true; // the backend row from the v1 registration
      await seed(2);

      final background = await worker(foreground: false).syncPendingReadings();
      expect(background.reason, SyncRunReason.awaitingForeground);
      expect(backend.requests, isEmpty);

      final foreground = await worker().syncPendingReadings();
      expect(foreground.reason, SyncRunReason.success);
      expect(backend.count('/weather/stations/mobile'), 1);
      expect(backend.requests.map((r) => r.body['version']), contains(2));
      expect(backend.collectPubkey, isNotNull);
    });

    test(
      'reinstall: prefs restored, collect key lost -> new key, re-register',
      () async {
        final old = await alreadyRegistered();
        // The Keystore entry did not survive the reinstall/restore.
        collectStore = syntheticCollectStore(seed: 99);
        await seed(2);

        final result = await worker().syncPendingReadings();

        final fresh = (await collectStore.load(syntheticAddress))!;
        expect(fresh.publicKeyHex, isNot(old.publicKeyHex));
        expect(result.reason, SyncRunReason.success);
        expect(result.acceptedCount, 2);
        expect(backend.count('/weather/stations/mobile'), 1);
        expect(backend.rotations, 1);
        expect(backend.collectPubkey, fresh.publicKeyHex);
      },
    );
  });

  group('COLLECT_KEY_MISMATCH', () {
    test(
      'a foreground run generates a new key and re-registers once',
      () async {
        final old = await alreadyRegistered();
        backend.collectPubkey = _oldKey; // rotated elsewhere; ours is refused
        await seed(3);

        final result = await worker().syncPendingReadings();

        final fresh = (await collectStore.load(syntheticAddress))!;
        expect(fresh.publicKeyHex, isNot(old.publicKeyHex));
        expect(result.reason, SyncRunReason.success);
        expect(result.acceptedCount, 3);
        expect(backend.count('/weather/stations/mobile'), 1);
        expect(backend.rotations, 1);
        expect(signer.openAttempts, 1);
        expect(backend.collectPubkey, fresh.publicKeyHex);
      },
    );

    test('a persistent mismatch re-registers ONCE per run, then stops', () async {
      await alreadyRegistered();
      backend.forceCollectMismatch = true;
      await seed(3);

      final result = await worker().syncPendingReadings();

      expect(backend.count('/weather/stations/mobile'), 1);
      expect(signer.openAttempts, 1);
      expect(result.acceptedCount, 0);
      expect(result.pendingCount, 3);
      expect(result.reason, SyncRunReason.rejected);
      expect(result.rejectedStatus, 403);
      // Refused at prepare, then one prepare retry after re-registration.
      expect(backend.count('/oracle/submit-data/prepare'), 2);
      expect(backend.count('/oracle/submit-data'), 0);
    });

    test(
      'a background run only records: open the app to re-register',
      () async {
        await alreadyRegistered();
        backend.collectPubkey = _oldKey;
        await seed(3);

        final result = await worker(foreground: false).syncPendingReadings();

        expect(result.reason, SyncRunReason.awaitingReRegistration);
        expect(result.message, contains('open the app'));
        expect(result.message, contains('re-register'));
        expect(result.pendingCount, 3);
        expect(backend.count('/weather/stations/mobile'), 0);
        expect(signer.openAttempts, 0);
        expect(
          backend.count('/oracle/submit-data/prepare'),
          1,
          reason: 'no retry storm',
        );
        expect(backend.count('/oracle/submit-data'), 0);
      },
    );
  });

  group('the collect key stays secret and spend-less', () {
    test('its seed is never logged or printed, nor in toString', () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
      try {
        await runZoned(
          () async {
            await seed(3);
            await worker().syncPendingReadings();
            await worker(foreground: false).syncPendingReadings();
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => logs.add(line),
          ),
        );
      } finally {
        debugPrint = original;
      }

      final seedHex = (await collectStorage.read(key: 'collect_key_seed'))!;
      final key = (await collectStore.load(syntheticAddress))!;
      final joined = logs.join('\n');
      expect(seedHex, hasLength(64));
      expect(joined, isNot(contains(seedHex)));
      expect(key.toString(), isNot(contains(seedHex)));
      expect(key.toString(), isNot(contains(key.publicKeyHex)));
      expect(jsonEncode({'k': key.toString()}), isNot(contains(seedHex)));
    });

    test('it can only sign a commit authorization for its own station', () {
      final source = File('lib/services/crypto/collect_key_store.dart')
          .readAsStringSync();
      // No raw signer, no seed, no arbitrary-message signing on the public API.
      final publicApi = source
          .split('\n')
          .where(
            (l) =>
                RegExp(r'^\s{2}(Future|String|Uint8List)').hasMatch(l) &&
                !RegExp(r'\s_\w+\(').hasMatch(l),
          )
          .join('\n');
      expect(publicApi, isNot(contains('sign(')));
      expect(publicApi, isNot(contains('seed')));
      expect(publicApi, isNot(contains('export')));
    });

    test('wallet management only wipes it; transfer and send paths cannot reach it', () {
      final importers = <String>[
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              RegExp(
                r"^import .*collect_key_store\.dart",
                multiLine: true,
              ).hasMatch(f.readAsStringSync()))
            f.path,
      ]..sort();
      expect(importers, [
        'lib/features/collector/data/repositories/collector_repository_impl.dart',
        'lib/features/collector/data/services/station_registration_service.dart',
        'lib/features/wallet/presentation/screens/wallet_screen.dart',
        'lib/services/background/sync_worker.dart',
      ]);
      final walletScreen = File('lib/features/wallet/presentation/screens/wallet_screen.dart').readAsStringSync();
      expect(walletScreen, contains('ref.read(collectKeyWiperProvider).wipe()'));
      expect(walletScreen, isNot(contains('collectKeyStoreProvider')));
      expect(walletScreen, isNot(contains('CollectKeyStore(')));
      expect(walletScreen, isNot(contains('signCommitAuthorization')));
      expect(walletScreen, isNot(contains('SecureKeyValueStorage.collectKey()')));
      // ...and the collector has no wallet-send code.
      final transfer = File('lib/services/crypto/signed_transfer.dart')
          .readAsStringSync();
      expect(transfer, isNot(contains('collect')));
    });

    test(
      'a commit signature is bound to commit-auth v2, not a transfer',
      () async {
        final key = await syntheticCollectKey();
        final signed = await key.signCommitAuthorization(commitId: 'c-1');

        final domain = TransferSigningDomain.configured;
        expect(
          utf8.decode(signed.message.sublist(0, 22)),
          'wrfcoin_commit_auth_v2',
        );
        expect(signed.publicKeyHex, key.publicKeyHex);
        expect(domain.chainId, isNotEmpty);
      },
    );
  });
}

Future<String?> registeredMarker() async =>
    (await SharedPreferences.getInstance()).getString(
      StationRegistrationService.registeredStationKey,
    );

class _FailingCollectStorage extends CountingKeyValueStorage {
  _FailingCollectStorage(this.failKey);
  final String failKey;
  @override
  Future<void> write({required String key, String? value}) async {
    if (key == failKey) throw StateError('synthetic corrupt collect store');
    await super.write(key: key, value: value);
  }
}
