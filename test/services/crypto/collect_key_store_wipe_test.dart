import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';

import '../../test_helpers/fake_station_backend.dart';
import '../../test_helpers/fakes.dart';

class _Storage extends InMemoryKeyValueStorage {
  int wipes = 0;
  bool fail = false;
  @override
  Future<void> deleteAll() async {
    wipes++;
    if (fail) throw StateError('synthetic deletion failure');
    await super.deleteAll();
  }
}

void main() {
  test('wallet capability is a wipe-only adapter, not a collect store', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final CollectKeyWiper wiper = container.read(collectKeyWiperProvider);
    expect(wiper, isNot(isA<CollectKeyStore>()));
  });
  test(
    'wipe erases collect seed and owner without touching a wallet store',
    () async {
      final collectStorage = _Storage();
      final walletStorage = InMemoryKeyValueStorage();
      await walletStorage.write(key: 'wrf_address', value: syntheticAddress);
      final store = syntheticCollectStore(storage: collectStorage);
      await store.createFresh(syntheticAddress);
      await store.wipe();
      expect(collectStorage.wipes, 1);
      expect(await collectStorage.read(key: 'collect_key_seed'), isNull);
      expect(await collectStorage.read(key: 'collect_key_owner'), isNull);
      expect(await store.load(syntheticAddress), isNull);
      expect(await walletStorage.read(key: 'wrf_address'), syntheticAddress);
    },
  );

  test(
    'wipe propagates storage failure so callers can retain the wallet',
    () async {
      final storage = _Storage();
      final store = syntheticCollectStore(storage: storage);
      await store.createFresh(syntheticAddress);
      storage.fail = true;
      await expectLater(store.wipe(), throwsStateError);
      expect(storage.wipes, 1);
      expect(await store.load(syntheticAddress), isNotNull);
    },
  );

  test('wipe is idempotent for an empty namespace', () async {
    final storage = _Storage();
    final store = syntheticCollectStore(storage: storage);
    await store.wipe();
    await store.wipe();
    expect(storage.wipes, 2);
    expect(await store.load(syntheticAddress), isNull);
  });
}
