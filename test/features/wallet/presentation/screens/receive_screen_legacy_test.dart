import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/receive_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../../../test_helpers/fakes.dart';

const _address = '0x465230af3383c16d024c5f4b87ed2d1b595be148';
const _canonical = '0x1747c0169753965c854230c59c876be0f9b5a275';

Future<void> _pump(WidgetTester tester, {String? scheme}) async {
  final storage = InMemoryKeyValueStorage();
  final isCanonical = scheme == KeyManager.canonicalKeyScheme;
  await storage.write(
    key: 'wrf_address',
    value: isCanonical ? _canonical : _address,
  );
  if (scheme != null) await storage.write(key: 'wrf_key_scheme', value: scheme);
  final biometric = BiometricService(
    client: FakeLocalAuthClient(authenticateResult: true),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyManagerProvider.overrideWithValue(
          KeyManager(biometric: biometric, storage: storage),
        ),
      ],
      child: const MaterialApp(home: ReceiveScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('canonical wallet: QR and copy equal the verified address', (
    tester,
  ) async {
    await _pump(tester, scheme: KeyManager.canonicalKeyScheme);
    final qr = tester.widget<AddressQr>(find.byType(AddressQr));
    expect(qr.address, _canonical);
    expect(find.text(_canonical), findsOneWidget);
    expect(find.text('Copy Address'), findsOneWidget);
    expect(find.byKey(const Key('receive-only-notice')), findsNothing);
  });

  for (final scheme in [KeyManager.legacyKeyScheme, null]) {
    testWidgets(
      'legacy/unmarked wallet ($scheme) withholds send-here controls',
      (tester) async {
        await _pump(tester, scheme: scheme);
        expect(find.byKey(const Key('receive-only-notice')), findsOneWidget);
        expect(
          find.textContaining('can receive but cannot spend'),
          findsOneWidget,
        );
        expect(find.byType(AddressQr), findsNothing);
        expect(find.text('Copy Address'), findsNothing);
        expect(find.byType(Switch), findsNothing);
        expect(find.text(_address), findsNothing);
      },
    );
  }
}
