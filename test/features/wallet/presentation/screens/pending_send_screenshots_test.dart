import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/pending_send.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/pending_send_provider.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../../test_helpers/app_harness.dart';
import '../../../../test_helpers/fakes.dart';
import '../../../../test_helpers/screenshot_fonts.dart';

const _wallet = '0x1234567890abcdef1234567890abcdef12345678';
final _now = DateTime.utc(2026, 11, 1, 12);

String _send(
  PendingSendPhase phase, {
  Duration age = const Duration(seconds: 45),
  int? block,
}) => PendingSend(
  from: _wallet,
  to: '0x2222222222222222222222222222222222222222',
  amountBaseUnits: '50000000',
  nonce: '7',
  submittedAt: _now.subtract(age),
  phase: phase,
  hash: List.filled(64, 'a').join(),
  blockHeight: block,
).encode();

Future<AppDatabase> _pumpWallet(
  WidgetTester tester, {
  required String saved,
  required String path,
  FakeWalletRepository? repository,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final db = createTestDatabase();
  addTearDown(db.close);
  await tester.pumpWidget(
    await buildTestApp(
      db: db,
      signedIn: true,
      walletSecureStorage: FakeWalletSecureStorage()..pendingSend = saved,
      walletRepository: repository,
      extraOverrides: [pendingSendClockProvider.overrideWithValue(() => _now)],
    ),
  );
  await pumpFrames(tester);
  final router = ProviderScope.containerOf(
    tester.element(find.byType(Router<Object>).first),
  ).read(appRouterProvider);
  router.go('/wallet');
  await pumpFrames(tester);
  if (path != '/wallet') unawaited(router.push(path));
  await pumpFrames(tester, frames: 8);
  return db;
}

/// The wallet page with a pending send, and the PR screenshots, rendered only
/// with SCREENSHOT_FONT_DIR set. See test_helpers/screenshot_fonts.dart.
void main() {
  testWidgets('the wallet page shows the row under the balance', (
    tester,
  ) async {
    await _pumpWallet(
      tester,
      saved: _send(PendingSendPhase.submitted),
      path: '/wallet',
    );
    expect(find.text('Transaction pending'), findsOneWidget);
    expect(find.textContaining('0.5 WRF to 0x222222'), findsOneWidget);
    expect(find.byKey(const Key('pending-send-dismiss')), findsNothing);
  });

  final failing = FakeWalletRepository()
    ..accountNonceResult = const Left(NetworkFailure());
  final states = <String, (String, String, FakeWalletRepository?)>{
    'wallet-pending': ('/wallet', _send(PendingSendPhase.submitted), null),
    'wallet-confirmed': (
      '/wallet',
      _send(PendingSendPhase.included, block: 4242),
      null,
    ),
    'wallet-overdue': (
      '/wallet',
      _send(PendingSendPhase.submitted, age: const Duration(minutes: 12)),
      null,
    ),
    'wallet-unreadable': (
      '/wallet',
      _send(PendingSendPhase.submitted),
      failing,
    ),
    'send-blocked': ('/wallet/send', _send(PendingSendPhase.submitted), null),
  };
  for (final state in states.entries) {
    for (final (name, size) in [
      ('phone-390', const Size(390, 844)),
      ('desktop-1280', const Size(1280, 800)),
    ]) {
      testWidgets('${state.key} $name', (tester) async {
        await loadScreenshotFonts();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (path, saved, repository) = state.value;
        await _pumpWallet(
          tester,
          saved: saved,
          path: path,
          repository: repository,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../../../docs/screens/pending_send/${state.key}-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
