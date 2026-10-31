import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/send_allowlist.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_security_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/address_book_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/recovery_phrase_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_allowlist_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../test_helpers/fakes.dart';

/// Screenshots for the phrase-free wallet PR: real widget renders with
/// synthetic fixtures (not a device run). Generate with:
///
///   TZ=UTC WALLET_SCREENSHOT_FONT=$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf \
///     flutter test --update-goldens test/features/wallet/wallet_safety_screenshots_test.dart
///
/// Skipped when WALLET_SCREENSHOT_FONT is unset (as in CI).
final _font = Platform.environment['WALLET_SCREENSHOT_FONT'];
final _now = DateTime.utc(2026, 11, 1, 12);
const _mom = '0x1747c0169753965c854230c59c876be0f9b5a275';
const _dad = '0x3f995ceb27e8177077dbed8b1e4f696af74da492';
const _shop = '0x8ba1f109551bd432803012645ac136ddd64dba72';
const _stranger = '0x2222222222222222222222222222222222222222';

List<AddressBookEntry> get _book => [
  AddressBookEntry(
    label: 'Mom',
    address: _mom,
    allowedFrom: _now.subtract(const Duration(days: 3)),
  ),
  AddressBookEntry(
    label: 'Dad',
    address: _dad,
    allowedFrom: _now.add(const Duration(hours: 20)),
  ),
  const AddressBookEntry(label: 'Coffee shop', address: _shop),
];

class _WalletNotifier extends WalletNotifier {
  @override
  Future<WalletModel?> build() async =>
      const WalletModel(address: _dad, balance: '1000000000');

  @override
  Future<void> refresh() async {}
}

class _TxNotifier extends TransactionsNotifier {
  @override
  Future<TransactionsState> build() async =>
      const TransactionsState(items: [], hasMore: false, loadingMore: false);

  @override
  Future<void> refresh() async {}
}

Future<void> _loadFonts() async {
  final dir = File(_font!).parent;
  Future<ByteData> bytes(String name) async =>
      ByteData.sublistView(File('${dir.path}/$name').readAsBytesSync());
  for (final family in ['Roboto', 'monospace']) {
    final loader = FontLoader(family);
    for (final f in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]) {
      loader.addFont(bytes(f));
    }
    await loader.load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(bytes('MaterialIcons-Regular.otf'))).load();
}

typedef _Shot = ({String name, Widget screen});

final _shots = <_Shot>[
  (name: 'contacts', screen: const AddressBookScreen()),
  (name: 'allowlist-pending', screen: const SendAllowlistScreen()),
  (name: 'view-phrase-confirm', screen: const RecoveryPhraseScreen()),
  (name: 'send-not-allowlisted', screen: const SendScreen()),
];

void main() {
  for (final shot in _shots) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        final file =
            '${shot.name}-${brightness.name}-${size.width.toInt()}.png';
        testWidgets('screenshot $file', (tester) async {
          await _loadFonts();
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final storage = InMemoryKeyValueStorage();
          await storage.write(key: 'wrf_address', value: _dad);
          await storage.write(
            key: 'wrf_key_scheme',
            value: KeyManager.canonicalKeyScheme,
          );
          final biometric = BiometricService(client: FakeLocalAuthClient());
          final router = GoRouter(
            initialLocation: '/x',
            routes: [GoRoute(path: '/x', builder: (_, _) => shot.screen)],
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                walletSecureStorageProvider.overrideWithValue(
                  FakeWalletSecureStorage(
                    addressBook: _book,
                    sendAllowlist: shot.name == 'allowlist-pending'
                        ? SendAllowlistSettings(
                            enabled: true,
                            turnsOffAt: _now.add(const Duration(hours: 23)),
                          )
                        : const SendAllowlistSettings(enabled: true),
                  ),
                ),
                allowlistClockProvider.overrideWithValue(() => _now),
                biometricServiceProvider.overrideWithValue(biometric),
                keyManagerProvider.overrideWithValue(
                  KeyManager(biometric: biometric, storage: storage),
                ),
                walletRepositoryProvider.overrideWithValue(
                  FakeWalletRepository(
                    estimateGasResult: const Right({
                      'feeBaseUnits': '1000',
                      'authoritative': true,
                    }),
                  ),
                ),
                walletProvider.overrideWith(_WalletNotifier.new),
                transactionsProvider.overrideWith(_TxNotifier.new),
              ],
              child: MaterialApp.router(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: brightness == Brightness.light
                    ? ThemeMode.light
                    : ThemeMode.dark,
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();

          if (shot.name == 'view-phrase-confirm') {
            await tester.enterText(
              find.byKey(const Key('recovery-confirm-field')),
              revealPhraseConfirmation,
            );
            FocusManager.instance.primaryFocus?.unfocus();
          }
          if (shot.name == 'send-not-allowlisted') {
            await tester.enterText(
              find.widgetWithText(TextFormField, 'Send to'),
              _stranger,
            );
            await tester.enterText(
              find.widgetWithText(TextFormField, 'Amount (WRF)'),
              '2.5',
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pump(const Duration(milliseconds: 500));
          }
          await tester.pumpAndSettle();

          if (shot.name == 'send-not-allowlisted') {
            expect(
              find.byKey(const Key('allowlist-recipient-blocked')),
              findsOneWidget,
            );
          }
          if (shot.name == 'allowlist-pending') {
            expect(find.text(sendAllowlistScopeNote), findsOneWidget);
          }
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../../../docs/screenshots/phrase-free-wallet/$file',
            ),
          );
        }, skip: _font == null);
      }
    }
  }
}
