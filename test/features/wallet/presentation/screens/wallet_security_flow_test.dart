import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/import_wallet_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/wallet_screen.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registration_service.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/referral/referral_service.dart';
import 'package:wrfcoin_mobile/services/security/screen_security_service.dart';

import '../../../../test_helpers/fakes.dart';
import '../../../../test_helpers/fake_station_backend.dart';

void main() {
  testWidgets('import flow verifies sampled mnemonic words before saving', (
    tester,
  ) async {
    final keyStorage = InMemoryKeyValueStorage();
    final walletStorage = FakeWalletSecureStorage();
    final screenSecurityClient = FakeScreenSecurityClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: keyStorage,
            ),
          ),
          biometricServiceProvider.overrideWithValue(
            BiometricService(
              client: FakeLocalAuthClient(authenticateResult: true),
            ),
          ),
          walletSecureStorageProvider.overrideWithValue(walletStorage),
          referralServiceProvider.overrideWithValue(_FakeReferralService()),
          screenSecurityClientProvider.overrideWithValue(screenSecurityClient),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const ImportWalletScreen(),
              ),
              GoRoute(
                path: '/wallet',
                builder: (context, state) => const Scaffold(
                  body: Center(child: Text('Wallet restored')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await _pumpFrame(tester);

    await tester.enterText(
      find.byType(TextFormField).first,
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    );
    await tester.tap(find.text('Verify Recovery'));
    await _pumpFrame(tester);

    final wordFields = find.byWidgetPredicate((widget) {
      if (widget is! TextField) return false;
      return widget.decoration?.labelText?.startsWith('Word #') ?? false;
    });
    expect(wordFields, findsNWidgets(3));

    const mnemonicWords = [
      'abandon',
      'abandon',
      'abandon',
      'abandon',
      'abandon',
      'abandon',
      'abandon',
      'abandon',
      'abandon',
      'abandon',
      'abandon',
      'about',
    ];

    for (final element in tester.widgetList<TextField>(wordFields)) {
      final label = element.decoration?.labelText ?? '';
      final match = RegExp(r'Word #(\d+)').firstMatch(label);
      expect(match, isNotNull);
      final index = int.parse(match!.group(1)!) - 1;
      await tester.enterText(
        find.byWidgetPredicate((widget) {
          return widget is TextField &&
              widget.decoration?.labelText == label &&
              widget.controller == element.controller;
        }),
        mnemonicWords[index],
      );
    }

    await tester.scrollUntilVisible(
      find.text('Complete Recovery'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpFrame(tester);
    await tester.tap(find.text('Complete Recovery'));
    await _pumpFrame(tester);

    expect(find.text('Wallet restored'), findsOneWidget);
    expect(await keyStorage.read(key: 'wrf_address'), isNotNull);
    expect(await keyStorage.read(key: 'wrf_mnemonic'), isNotNull);
    expect(await keyStorage.read(key: 'wrf_private_key'), isNotNull);
    expect(walletStorage.backupConfirmed, isTrue);
    expect(screenSecurityClient.enableCalls, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrame(tester);
    expect(screenSecurityClient.disableCalls, greaterThan(0));
  });

  testWidgets('recovery requires successful biometric authentication', (
    tester,
  ) async {
    final keyStorage = InMemoryKeyValueStorage();
    final walletStorage = FakeWalletSecureStorage();
    final screenSecurityClient = FakeScreenSecurityClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: keyStorage,
            ),
          ),
          biometricServiceProvider.overrideWithValue(
            BiometricService(
              client: FakeLocalAuthClient(authenticateResult: false),
            ),
          ),
          walletSecureStorageProvider.overrideWithValue(walletStorage),
          referralServiceProvider.overrideWithValue(_FakeReferralService()),
          screenSecurityClientProvider.overrideWithValue(screenSecurityClient),
        ],
        child: const MaterialApp(home: ImportWalletScreen()),
      ),
    );

    await _pumpFrame(tester);

    await tester.enterText(
      find.byType(TextFormField).first,
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    );
    await tester.tap(find.text('Verify Recovery'));
    await _pumpFrame(tester);

    final wordFields = find.byWidgetPredicate((widget) {
      if (widget is! TextField) return false;
      return widget.decoration?.labelText?.startsWith('Word #') ?? false;
    });
    expect(wordFields, findsNWidgets(3));

    for (final element in tester.widgetList<TextField>(wordFields)) {
      final label = element.decoration?.labelText ?? '';
      final match = RegExp(r'Word #(\d+)').firstMatch(label);
      expect(match, isNotNull);
      final index = int.parse(match!.group(1)!) - 1;
      await tester.enterText(
        find.byWidgetPredicate((widget) {
          return widget is TextField &&
              widget.decoration?.labelText == label &&
              widget.controller == element.controller;
        }),
        index == 11 ? 'about' : 'abandon',
      );
    }

    await tester.scrollUntilVisible(
      find.text('Complete Recovery'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpFrame(tester);
    await tester.tap(find.text('Complete Recovery'));
    await _pumpFrame(tester);

    expect(await keyStorage.read(key: 'wrf_address'), isNull);
    expect(await keyStorage.read(key: 'wrf_mnemonic'), isNull);
    expect(walletStorage.backupConfirmed, isTrue);
    expect(find.text('Import / Restore Wallet'), findsOneWidget);
    expect(screenSecurityClient.enableCalls, greaterThan(0));
  });

  testWidgets('emergency wipe clears wallet data and returns to empty state', (
    tester,
  ) async {
    final keyStorage = InMemoryKeyValueStorage();
    await keyStorage.write(
      key: 'wrf_address',
      value: '0x1234567890abcdef1234567890abcdef12345678',
    );

    final walletStorage = FakeWalletSecureStorage(
      backupConfirmed: true,
      isSocial: true,
      addressBook: [AddressBookEntry(label: 'Alice', address: 'wrf1abc123')],
    );

    FlutterSecureStorage.setMockInitialValues({});
    final collectStore = CollectKeyStore();
    SharedPreferences.setMockInitialValues(
      await registeredPrefsFor(collectStore),
    );
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(
            ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://localhost'))),
          ),
          walletRepositoryProvider.overrideWithValue(
            FakeWalletRepository(
              wallet: const WalletModel(
                address: '0x1234567890abcdef1234567890abcdef12345678',
                balance: '42.00',
                transactions: 0,
              ),
            ),
          ),
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: keyStorage,
            ),
          ),
          walletSecureStorageProvider.overrideWithValue(walletStorage),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/wallet',
            routes: [
              GoRoute(
                path: '/wallet',
                builder: (context, state) => const WalletScreen(),
              ),
            ],
          ),
        ),
      ),
    );

    await _pumpFrame(tester);

    expect(find.text('Emergency Wipe'), findsOneWidget);

    await tester.ensureVisible(find.text('Emergency Wipe'));
    await tester.pump();
    await tester.tap(find.text('Emergency Wipe'));
    await _pumpFrame(tester);

    await tester.enterText(find.byType(TextField).first, 'WIPE');
    await tester.pump();
    await tester.tap(find.text('Wipe now'));
    await _pumpFrame(tester);

    expect(walletStorage.clearWalletDataCalls, 1);
    expect(await collectStore.load(syntheticAddress), isNull);
    expect(
      prefs.getString(StationRegistrationService.registeredStationKey),
      isNull,
    );
    expect(await keyStorage.read(key: 'wrf_address'), isNull);
    expect(await keyStorage.read(key: 'wrf_mnemonic'), isNull);
    expect(await keyStorage.read(key: 'wrf_private_key'), isNull);
    expect(find.text('No Wallet Found'), findsOneWidget);
  });
}

Future<void> _pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _FakeReferralService extends ReferralService {
  _FakeReferralService()
    : super(
        apiClient: ApiClient(
          dio: Dio(BaseOptions(baseUrl: 'http://localhost')),
        ),
      );

  @override
  Future<bool> trackReferralAttributionOnSignup({
    required String refereeAddress,
  }) async {
    return false;
  }
}
