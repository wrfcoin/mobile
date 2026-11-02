import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/passkey_wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/passkey_wallet_screen.dart';

import '../../../../test_helpers/fakes.dart';
import '../../../../test_helpers/screenshot_fonts.dart';

class _NoPhoneWallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => null;
}

class _Balance extends FakeWalletRepository {
  @override
  Future<Either<Failure, WalletModel>> getWallet(String address) async =>
      Right(WalletModel(address: address, balance: '150000000'));
}

/// PR screenshots, rendered only with SCREENSHOT_FONT_DIR set. The address is a
/// synthetic fixture.
void main() {
  const shots = {
    'empty': <String, Object>{},
    'saved': <String, Object>{
      PasskeyAddressNotifier.storageKey:
          '0x1747c0169753965c854230c59c876be0f9b5a275',
    },
  };
  for (final MapEntry(key: state, value: prefs) in shots.entries) {
    for (final (name, size) in const [
      ('phone-390', Size(390, 1250)),
      ('desktop-1280', Size(1280, 1100)),
    ]) {
      testWidgets('$state $name', (tester) async {
        await loadScreenshotFonts();
        // Addresses ask for monospace, which the tests don't have.
        final mono = FontLoader('monospace')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  '${Platform.environment['SCREENSHOT_FONT_DIR']}/Roboto-Regular.ttf',
                ).readAsBytesSync(),
              ),
            ),
          );
        await mono.load();
        SharedPreferences.setMockInitialValues(prefs);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              walletProvider.overrideWith(_NoPhoneWallet.new),
              walletRepositoryProvider.overrideWithValue(_Balance()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme.copyWith(
                textTheme: AppTheme.lightTheme.textTheme.apply(
                  fontFamily: 'Roboto',
                ),
              ),
              home: const PasskeyWalletScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../../../docs/screens/passkey_wallet/$state-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
