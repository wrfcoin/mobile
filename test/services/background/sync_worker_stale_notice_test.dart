import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

class _Online implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _Db extends AppDatabase {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> close() async {}
  Future<void> dispose() => super.close();
}

class _Wallet extends WalletSecureStorage {
  @override
  Future<String?> getWalletAddress() async => '0x${'12' * 20}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'background stale drops leave a durable notice after a later idle run',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = _Db();
      addTearDown(db.dispose);
      final clock = DateTime.utc(2026, 9, 29, 12);
      await db.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 1,
          longitude: 2,
          pressureHpa: 1000,
          timestamp: clock.subtract(const Duration(minutes: 51)),
        ),
      );
      final worker = SyncWorker(
        connectivity: _Online(),
        walletSecureStorage: _Wallet(),
        dbFactory: () => db,
        now: () => clock,
        canStartLogin: false,
        repositoryFactory: (_) =>
            throw StateError('No API or signer may be reached'),
      );
      final result = await worker.syncPendingReadings();
      expect(result.droppedStaleCount, 1);
      await worker.syncPendingReadings();
      final notice = await db.getSyncMetadata('sensor_readings_stale_notice');
      expect(notice?.pendingCount, 1);
    },
  );
}
