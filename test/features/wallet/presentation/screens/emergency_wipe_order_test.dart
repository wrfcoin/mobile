import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registration_service.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/wallet_screen.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../../../test_helpers/fakes.dart';

const _address = '0x1234567890abcdef1234567890abcdef12345678';
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _WalletKeys extends InMemoryKeyValueStorage {
  _WalletKeys(this.events);
  final List<String> events;
  bool fail = false;
  @override
  Future<void> deleteAll() async {
    events.add('wallet keys');
    if (fail) throw StateError('synthetic key deletion failure');
    await super.deleteAll();
  }
}

class _WalletData extends FakeWalletSecureStorage {
  _WalletData(this.events, {this.fail = false});
  final List<String> events;
  bool fail;
  String? address = _address;
  @override
  Future<String?> getWalletAddress() async => address;
  @override
  Future<void> clearWalletData() async {
    events.add('wallet metadata');
    if (fail) throw StateError('synthetic metadata failure');
    await super.clearWalletData();
    address = null;
  }
}

class _MarkerPreferences extends Fake implements SharedPreferences {
  _MarkerPreferences(this.delegate);
  final SharedPreferences delegate;
  bool fail = false;
  @override
  bool? getBool(String key) => delegate.getBool(key);
  @override
  String? getString(String key) => delegate.getString(key);
  @override
  Future<bool> remove(String key) async => fail ? false : delegate.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> events;
  late Completer<void> collectGate;
  late _WalletKeys walletKeys;
  late _WalletData walletData;
  late SharedPreferences prefs;
  late _MarkerPreferences marker;

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    bool collectFails = false,
    bool metadataFails = false,
    bool keysFail = false,
    bool markerFails = false,
  }) async {
    events = [];
    collectGate = Completer<void>();
    walletKeys = _WalletKeys(events)..fail = keysFail;
    await walletKeys.write(
      key: 'wrf_private_key',
      value: 'synthetic-private-key',
    );
    await walletKeys.write(key: 'wrf_address', value: _address);
    walletData = _WalletData(events, fail: metadataFails);
    SharedPreferences.setMockInitialValues({
      StationRegistrationService.registeredStationKey: 'synthetic marker',
    });
    prefs = await SharedPreferences.getInstance();
    marker = _MarkerPreferences(prefs)..fail = markerFails;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method != 'deleteAll') return null;
          final options = (call.arguments as Map)['options'] as Map;
          expect(options['storageNamespace'], 'wrfcoin_collect_key');
          events.add('collect start');
          await collectGate.future;
          if (collectFails) {
            throw PlatformException(code: 'synthetic_collect_failure');
          }
          events.add('collect done');
          return null;
        });
    addTearDown(() {
      if (!collectGate.isCompleted) collectGate.complete();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });
    final router = GoRouter(
      initialLocation: '/wallet',
      routes: [
        GoRoute(path: '/wallet', builder: (_, _) => const WalletScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(marker),
          apiClientProvider.overrideWithValue(ApiClient(dio: Dio())),
          walletRepositoryProvider.overrideWithValue(
            FakeWalletRepository(
              wallet: const WalletModel(address: _address, balance: '1'),
            ),
          ),
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: walletKeys,
            ),
          ),
          walletSecureStorageProvider.overrideWithValue(walletData),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await frames(tester);
    await tester.ensureVisible(find.text('Emergency Wipe'));
    await tester.pump();
    await tester.tap(find.text('Emergency Wipe'));
    await frames(tester);
    await tester.enterText(find.byType(TextField).first, 'WIPE');
    await tester.pump();
    await tester.tap(find.text('Wipe now'));
    await frames(tester);
  }

  testWidgets('wallet and marker wait until collect-key deletion completes', (
    tester,
  ) async {
    await mount(tester);
    try {
      expect(events, ['collect start']);
      expect(await walletKeys.read(key: 'wrf_address'), _address);
      expect(
        prefs.getString(StationRegistrationService.registeredStationKey),
        isNotNull,
      );
    } finally {
      collectGate.complete();
      await frames(tester);
    }
    expect(events, [
      'collect start',
      'collect done',
      'wallet keys',
      'wallet metadata',
    ]);
    expect(await walletKeys.read(key: 'wrf_address'), isNull);
    expect(
      prefs.getString(StationRegistrationService.registeredStationKey),
      isNull,
    );
  });

  testWidgets(
    'failed collect deletion keeps wallet and reports a stopped wipe',
    (tester) async {
      await mount(tester, collectFails: true);
      collectGate.complete();
      await frames(tester);
      expect(await walletKeys.read(key: 'wrf_address'), _address);
      expect(events, ['collect start']);
      expect(walletData.clearWalletDataCalls, 0);
      expect(
        prefs.getString(StationRegistrationService.registeredStationKey),
        isNotNull,
      );
      expect(find.textContaining('Wallet data was kept'), findsOneWidget);
      expect(find.text('Wallet wiped from this device'), findsNothing);
    },
  );

  testWidgets('marker failure stops before wallet cleanup', (tester) async {
    await mount(tester, markerFails: true);
    collectGate.complete();
    await frames(tester);
    expect(events, ['collect start', 'collect done']);
    expect(
      await walletKeys.read(key: 'wrf_private_key'),
      'synthetic-private-key',
    );
    expect(await walletData.getWalletAddress(), _address);
    expect(walletData.clearWalletDataCalls, 0);
    expect(find.textContaining('Emergency wipe incomplete'), findsOneWidget);
    expect(find.text('Wallet wiped from this device'), findsNothing);
  });

  testWidgets(
    'key failure retains address metadata and permits a later retry',
    (tester) async {
      await mount(tester, keysFail: true);
      collectGate.complete();
      await frames(tester);
      expect(events, ['collect start', 'collect done', 'wallet keys']);
      expect(
        await walletKeys.read(key: 'wrf_private_key'),
        'synthetic-private-key',
      );
      expect(await walletData.getWalletAddress(), _address);
      expect(walletData.clearWalletDataCalls, 0);
      expect(find.textContaining('Emergency wipe incomplete'), findsOneWidget);
      expect(find.text('Wallet wiped from this device'), findsNothing);
      walletKeys.fail = false;
      // The failure snackbar can cover the retry action as content grows.
      ScaffoldMessenger.of(tester.element(find.byType(WalletScreen)))
          .removeCurrentSnackBar();
      await tester.pump();
      await tester.ensureVisible(find.text('Emergency Wipe'));
      await tester.pump();
      await tester.tap(find.text('Emergency Wipe'));
      await frames(tester);
      await tester.enterText(find.byType(TextField).first, 'WIPE');
      await tester.pump();
      await tester.tap(find.text('Wipe now'));
      await frames(tester);
      expect(await walletKeys.read(key: 'wrf_private_key'), isNull);
      expect(await walletData.getWalletAddress(), isNull);
      for (
        var i = 0;
        i < 10 && find.text('Wallet wiped from this device').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Wallet wiped from this device'), findsOneWidget);
    },
  );

  testWidgets(
    'metadata failure follows key deletion and cannot orphan a private key',
    (tester) async {
      await mount(tester, metadataFails: true);
      collectGate.complete();
      await frames(tester);
      expect(events, [
        'collect start',
        'collect done',
        'wallet keys',
        'wallet metadata',
      ]);
      expect(await walletKeys.read(key: 'wrf_private_key'), isNull);
      expect(await walletData.getWalletAddress(), _address);
      expect(find.textContaining('Emergency wipe incomplete'), findsOneWidget);
      expect(find.text('Wallet wiped from this device'), findsNothing);
    },
  );
}
