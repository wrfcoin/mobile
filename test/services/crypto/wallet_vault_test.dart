import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_vault.dart';

import '../../test_helpers/fakes.dart';

// Fixture values only: not a real phrase or key.
const _mnemonic = 'fixture alpha bravo charlie delta echo foxtrot golf';
const _privateKey = 'fixture-private-key-00112233445566778899aabbccddeeff';
const _loginKey = 'fixture-login-key-ffeeddccbbaa99887766554433221100';
const _address = 'wrf1fixturestationwallet000000000000';
const _loginAddress = '0xfixturelegacyloginaddress00000000000000';
const _secrets = [_mnemonic, _privateKey, _loginKey];

/// Map-backed storage that can simulate a process kill after a number of
/// writes (the write that would be number [killAfterWrites] + 1 throws before
/// it lands) and can corrupt writes to one key.
class _Storage implements KeyValueStorage {
  final Map<String, String?> values = <String, String?>{};
  int writes = 0;
  int? killAfterWrites;
  String? corruptKeySuffix;

  @override
  Future<void> deleteAll() async => values.clear();

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, String? value}) async {
    if (killAfterWrites != null && writes >= killAfterWrites!) {
      throw const _Killed();
    }
    writes++;
    if (value != null &&
        corruptKeySuffix != null &&
        key.endsWith(corruptKeySuffix!)) {
      values[key] = '${value}x';
      return;
    }
    values[key] = value;
  }

  Map<String, String?> snapshot() => Map<String, String?>.of(values);

  Map<String, String?> legacySlots() => {
    for (final key in WalletVault.legacyFields.keys) key: values[key],
  };
}

class _Killed implements Exception {
  const _Killed();
}

Future<void> _seedLegacy(KeyValueStorage storage) async {
  final manager = KeyManager(
    biometric: BiometricService(client: FakeLocalAuthClient()),
    storage: storage,
  );
  await manager.storeKeys(
    mnemonic: _mnemonic,
    privateKey: _privateKey,
    address: _address,
    loginPrivateKey: _loginKey,
    loginAddress: _loginAddress,
  );
  await storage.write(key: 'wrf_backup_confirmed', value: 'true');
  await storage.write(key: 'wrf_is_social', value: 'false');
  await manager.storeAuthSession(jwt: 'fixture-jwt', expiresInSeconds: 3600);
}

KeyManager _manager(KeyValueStorage storage) => KeyManager(
  biometric: BiometricService(client: FakeLocalAuthClient()),
  storage: storage,
);

/// Every KeyManager read the 19 call sites depend on, in one record.
Future<Map<String, Object?>> _keyManagerView(KeyValueStorage storage) async {
  final m = _manager(storage);
  return {
    'hasWallet': await m.hasWallet(),
    'address': await m.getAddress(),
    'loginAddress': await m.getLoginAddress(),
    'loginPrivateKey': await m.getLoginPrivateKey(),
    'keyScheme': await m.getKeyScheme(),
    'canSign': await m.canSignTransactions(),
    'ownLegacyAlias': await m.getOwnLegacyAlias(),
    'privateKey': await m.getPrivateKey(),
    'mnemonic': await m.getMnemonic(),
    'hasAuthSession': await m.hasAuthSession(),
    'authToken': await m.getAuthToken(),
  };
}

Future<List<String>> _captureLogs(Future<void> Function() body) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return logs;
}

void main() {
  late _Storage storage;
  var nextId = 0;
  WalletVault vault() =>
      WalletVault(storage: storage, newId: () => 'fixture${nextId++}');

  setUp(() async {
    nextId = 0;
    storage = _Storage();
    await _seedLegacy(storage);
    storage.writes = 0;
  });

  group('lossless migration', () {
    test('copies every legacy slot and commits the station wallet', () async {
      final legacyBefore = storage.legacySlots();
      final viewBefore = await _keyManagerView(storage);

      expect(await vault().migrateLegacy(), WalletMigrationResult.migrated);

      // Legacy slots are untouched and KeyManager reads exactly what it did.
      expect(storage.legacySlots(), legacyBefore);
      expect(await _keyManagerView(storage), viewBefore);

      final v = vault();
      final wallets = await v.listWallets();
      expect(wallets, hasLength(1));
      final w = wallets!.single;
      expect(w.address, _address);
      expect(w.stationBound, isTrue);
      expect(await v.activeWalletId(), w.id);
      expect((await v.stationWallet())!.id, w.id);
      for (final entry in WalletVault.legacyFields.entries) {
        expect(
          await v.readSlot(w.id, entry.value),
          legacyBefore[entry.key],
          reason: entry.value,
        );
      }
    });

    test('the index holds the address but no key material', () async {
      await vault().migrateLegacy();
      final index = storage.values[WalletVault.indexKey]!;
      expect(jsonDecode(index), isA<List<dynamic>>());
      for (final secret in _secrets) {
        expect(index.contains(secret), isFalse);
      }
      for (final key in storage.values.keys) {
        expect(key.contains(_address), isFalse, reason: key);
      }
    });

    test('the auth session stays a single slot and is not copied', () async {
      await vault().migrateLegacy();
      final copied = storage.values.entries.where(
        (e) => e.key.startsWith('wrf_w:') && e.value == 'fixture-jwt',
      );
      expect(copied, isEmpty);
    });

    test('absent optional legacy fields copy as absent', () async {
      storage = _Storage();
      await storage.write(key: 'wrf_mnemonic', value: _mnemonic);
      await storage.write(key: 'wrf_private_key', value: _privateKey);
      await storage.write(key: 'wrf_address', value: _address);

      expect(await vault().migrateLegacy(), WalletMigrationResult.migrated);
      final v = vault();
      final id = (await v.activeWalletId())!;
      expect(await v.readSlot(id, 'key_scheme'), isNull);
      expect(await v.readSlot(id, 'login_private_key'), isNull);
      expect(
        await _manager(storage).getKeyScheme(),
        KeyManager.legacyKeyScheme,
      );
    });

    test('no legacy wallet writes nothing', () async {
      storage = _Storage();
      expect(
        await vault().migrateLegacy(),
        WalletMigrationResult.noLegacyWallet,
      );
      expect(storage.values, isEmpty);
    });

    test(
      'a legacy wallet without its mnemonic or key writes nothing',
      () async {
        await storage.write(key: 'wrf_mnemonic', value: null);
        final before = storage.snapshot();
        storage.writes = 0;
        expect(
          await vault().migrateLegacy(),
          WalletMigrationResult.abortedIncompleteLegacy,
        );
        expect(storage.writes, 0);
        expect(storage.snapshot(), before);
      },
    );

    test('a copy that reads back differently is removed and aborts', () async {
      final before = storage.snapshot();
      storage.corruptKeySuffix = ':private_key';
      expect(
        await vault().migrateLegacy(),
        WalletMigrationResult.abortedVerifyMismatch,
      );
      storage.corruptKeySuffix = null;

      expect(storage.values[WalletVault.indexKey], isNull);
      expect(storage.values[WalletVault.activeKey], isNull);
      for (final field in WalletVault.legacyFields.values) {
        expect(storage.values[WalletVault.slotKey('fixture0', field)], isNull);
      }
      expect(storage.legacySlots(), {
        for (final k in WalletVault.legacyFields.keys) k: before[k],
      });

      // A clean re-run then succeeds.
      expect(await vault().migrateLegacy(), WalletMigrationResult.migrated);
    });
  });

  group('interrupted migration', () {
    // 8 slot copies + index + active pointer.
    const totalWrites = 10;
    const indexWrite = 8;

    test('a kill before the commit leaves legacy intact and usable', () async {
      final legacyBefore = storage.legacySlots();
      final viewBefore = await _keyManagerView(storage);

      for (var kill = 0; kill <= indexWrite; kill++) {
        nextId = 0;
        storage = _Storage();
        await _seedLegacy(storage);
        storage.writes = 0;
        storage.killAfterWrites = kill;

        await expectLater(
          vault().migrateLegacy(),
          throwsA(isA<_Killed>()),
          reason: 'kill after $kill writes',
        );
        storage.killAfterWrites = null;

        expect(storage.values[WalletVault.indexKey], isNull, reason: '$kill');
        expect(storage.legacySlots(), legacyBefore, reason: '$kill');
        expect(await _keyManagerView(storage), viewBefore, reason: '$kill');
        expect(await vault().listWallets(), isNull, reason: '$kill');

        // Restart: the migration runs again from the start and commits.
        expect(
          await vault().migrateLegacy(),
          WalletMigrationResult.migrated,
          reason: '$kill',
        );
        final v = vault();
        final id = (await v.activeWalletId())!;
        expect(await v.readSlot(id, 'mnemonic'), _mnemonic, reason: '$kill');
        expect(await v.readSlot(id, 'private_key'), _privateKey);
        expect((await v.stationWallet())!.address, _address);
      }
    });

    test(
      'a kill after the commit, before the active pointer, still resolves',
      () async {
        storage.killAfterWrites = totalWrites - 1;
        await expectLater(vault().migrateLegacy(), throwsA(isA<_Killed>()));
        storage.killAfterWrites = null;

        expect(storage.values[WalletVault.activeKey], isNull);
        final v = vault();
        final station = (await v.stationWallet())!;
        expect(await v.activeWalletId(), station.id);
        expect(await v.readSlot(station.id, 'mnemonic'), _mnemonic);
        expect(await v.migrateLegacy(), WalletMigrationResult.alreadyMigrated);
      },
    );

    test('a restart reusing an id overwrites stale partial slots', () async {
      // A killed run left a stray value under the id the next run picks.
      await storage.write(
        key: WalletVault.slotKey('fixture0', 'is_social'),
        value: 'stale',
      );
      await storage.write(key: 'wrf_is_social', value: null);
      expect(await vault().migrateLegacy(), WalletMigrationResult.migrated);
      expect(await vault().readSlot('fixture0', 'is_social'), isNull);
    });
  });

  group('idempotent re-run', () {
    test('a second run reads only the index and writes nothing', () async {
      expect(await vault().migrateLegacy(), WalletMigrationResult.migrated);
      final after = storage.snapshot();
      storage.writes = 0;

      for (var i = 0; i < 3; i++) {
        expect(
          await vault().migrateLegacy(),
          WalletMigrationResult.alreadyMigrated,
        );
      }
      expect(storage.writes, 0);
      expect(storage.snapshot(), after);
      expect(await vault().listWallets(), hasLength(1));
    });
  });

  group('station-bound wallet', () {
    Future<String> addSecondWallet() async {
      final wallets = (await vault().listWallets())!;
      const other = VaultWallet(
        id: 'other',
        label: 'Spending',
        address: 'wrf1fixtureotherwallet00000000000000',
        createdAt: '2026-10-28T00:00:00.000Z',
        stationBound: false,
      );
      await storage.write(
        key: WalletVault.indexKey,
        value: jsonEncode([...wallets.map((w) => w.toJson()), other.toJson()]),
      );
      await storage.write(
        key: WalletVault.slotKey('other', 'mnemonic'),
        value: 'fixture other phrase',
      );
      return other.id;
    }

    test(
      'removing the station wallet is refused and changes nothing',
      () async {
        await vault().migrateLegacy();
        await addSecondWallet();
        final station = (await vault().stationWallet())!;
        final before = storage.snapshot();

        await expectLater(
          vault().removeWallet(station.id),
          throwsA(
            isA<WalletRemovalRefused>().having(
              (e) => e.reason,
              'reason',
              WalletRemovalRefusal.stationWallet,
            ),
          ),
        );
        expect(storage.snapshot(), before);
      },
    );

    test('removal fails closed without a readable index', () async {
      await expectLater(
        vault().removeWallet('fixture0'),
        throwsA(
          isA<WalletRemovalRefused>().having(
            (e) => e.reason,
            'reason',
            WalletRemovalRefusal.indexUnavailable,
          ),
        ),
      );
      await vault().migrateLegacy();
      await storage.write(key: WalletVault.indexKey, value: '{not json');
      await expectLater(
        vault().removeWallet('fixture0'),
        throwsA(isA<WalletRemovalRefused>()),
      );
      expect(
        storage.values[WalletVault.slotKey('fixture0', 'mnemonic')],
        _mnemonic,
      );
    });

    test('an unknown id is refused', () async {
      await vault().migrateLegacy();
      await expectLater(
        vault().removeWallet('missing'),
        throwsA(
          isA<WalletRemovalRefused>().having(
            (e) => e.reason,
            'reason',
            WalletRemovalRefusal.unknownWallet,
          ),
        ),
      );
    });

    test('another wallet can be removed; the station wallet is kept', () async {
      await vault().migrateLegacy();
      final other = await addSecondWallet();
      await storage.write(key: WalletVault.activeKey, value: other);
      final station = (await vault().stationWallet())!;

      await vault().removeWallet(other);

      final wallets = (await vault().listWallets())!;
      expect(wallets.map((w) => w.id), [station.id]);
      expect(storage.values[WalletVault.slotKey(other, 'mnemonic')], isNull);
      expect(await vault().readSlot(station.id, 'mnemonic'), _mnemonic);
      expect(await vault().activeWalletId(), station.id);
      expect(storage.legacySlots()['wrf_mnemonic'], _mnemonic);
    });
  });

  group('flag off', () {
    Future<ProviderContainer> container({required bool enabled}) async {
      SharedPreferences.setMockInitialValues({
        if (enabled) 'ff_enableMultiWallet': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          keyValueStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the flag defaults to off', () async {
      expect(const FeatureFlags().enableMultiWallet, isFalse);
      final c = await container(enabled: false);
      expect(c.read(featureFlagsProvider).enableMultiWallet, isFalse);
    });

    test('startup with the flag off reads and writes nothing', () async {
      final before = storage.snapshot();
      final viewBefore = await _keyManagerView(storage);
      final c = await container(enabled: false);
      storage.writes = 0;

      expect(await migrateWalletVaultIfEnabled(c), isNull);
      expect(storage.writes, 0);
      expect(storage.snapshot(), before);
      expect(await _keyManagerView(storage), viewBefore);
    });

    test('startup with the flag on migrates once', () async {
      final c = await container(enabled: true);
      expect(
        await migrateWalletVaultIfEnabled(c),
        WalletMigrationResult.migrated,
      );
      expect(
        await migrateWalletVaultIfEnabled(c),
        WalletMigrationResult.alreadyMigrated,
      );
    });

    test('a failing migration never throws at startup', () async {
      final c = await container(enabled: true);
      storage.killAfterWrites = 0;
      expect(await migrateWalletVaultIfEnabled(c), isNull);
      storage.killAfterWrites = null;
      expect(storage.values[WalletVault.indexKey], isNull);
    });

    test('KeyManager reads legacy slots even after a migration', () async {
      final viewBefore = await _keyManagerView(storage);
      await vault().migrateLegacy();
      // Diverge the vault copy: KeyManager must not see it.
      final id = (await vault().activeWalletId())!;
      await storage.write(
        key: WalletVault.slotKey(id, 'address'),
        value: 'wrf1divergedcopy',
      );
      expect(await _keyManagerView(storage), viewBefore);
    });

    test('Emergency Wipe removes the vault copies too', () async {
      await vault().migrateLegacy();
      await _manager(storage).deleteAll();
      expect(storage.values, isEmpty);
      expect(await vault().listWallets(), isNull);
    });
  });

  test('no log line contains key material', () async {
    final logs = await _captureLogs(() async {
      await vault().migrateLegacy();
      await vault().migrateLegacy();
      storage = _Storage();
      await _seedLegacy(storage);
      storage.corruptKeySuffix = ':mnemonic';
      await vault().migrateLegacy();
      storage.corruptKeySuffix = null;
      storage.killAfterWrites = 0;
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await (() async {
              SharedPreferences.setMockInitialValues({
                'ff_enableMultiWallet': true,
              });
              return SharedPreferences.getInstance();
            })(),
          ),
          keyValueStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(c.dispose);
      await migrateWalletVaultIfEnabled(c);
    });

    expect(logs, isNotEmpty);
    for (final line in logs) {
      for (final secret in [..._secrets, _address, _loginAddress]) {
        expect(line.contains(secret), isFalse, reason: line);
      }
      expect(line.contains('wrf_w:'), isFalse, reason: line);
    }
  });
}
