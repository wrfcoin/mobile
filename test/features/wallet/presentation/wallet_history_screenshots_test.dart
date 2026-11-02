import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';

import '../../../test_helpers/app_harness.dart';
import '../../../test_helpers/screenshot_fonts.dart';

const _own = '0x1234567890abcdef1234567890abcdef12345678';
const _other = '0x1747000000000000000000000000000000a275';

class _Rows extends TransactionsNotifier {
  @override
  Future<TransactionsState> build() async => const TransactionsState(
    items: [
      TransactionModel(
        hash: '0xaaaa',
        blockNumber: 11768,
        from: _own,
        to: _other,
        value: '50000000',
        type: 'transfer',
        direction: 'outgoing',
        settlement: 'included',
      ),
      TransactionModel(
        hash: '0xbbbb',
        blockNumber: 11000,
        from: _other,
        to: _own,
        value: '100000000000',
        type: 'transfer',
        direction: 'incoming',
        settlement: 'included',
      ),
    ],
    credits: [
      TransactionModel(
        hash: '',
        eventId: 'contribution:one',
        from: '',
        to: _own,
        value: '12500000',
        type: 'weather_reward',
        direction: 'incoming',
        settlement: 'paid',
      ),
    ],
    hasMore: false,
    loadingMore: false,
    creditsTruncated: true,
    complete: false,
    windowStartHeight: 1,
  );
}

class _Failed extends TransactionsNotifier {
  @override
  Future<TransactionsState> build() async =>
      throw const ServerFailure('Not found', statusCode: 404);
}

/// PR screenshots, rendered only with SCREENSHOT_FONT_DIR set. See
/// test_helpers/screenshot_fonts.dart.
void main() {
  final states = <String, TransactionsNotifier Function()>{
    'rows': _Rows.new,
    'error': _Failed.new,
  };
  for (final state in states.entries) {
    for (final (name, size) in [
      ('phone-390', const Size(390, 1250)),
      ('desktop-1280', const Size(1280, 1000)),
    ]) {
      testWidgets('${state.key} $name', (tester) async {
        await loadScreenshotFonts();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              const EventChannel(
                'dev.fluttercommunity.plus/connectivity_status',
              ),
              MockStreamHandler.inline(onListen: (_, _) {}),
            );
        SharedPreferences.setMockInitialValues(<String, Object>{});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = createTestDatabase();
        addTearDown(db.close);
        await tester.pumpWidget(
          await buildTestApp(
            db: db,
            signedIn: true,
            extraOverrides: [transactionsProvider.overrideWith(state.value)],
          ),
        );
        await pumpFrames(tester);
        ProviderScope.containerOf(
          tester.element(find.byType(Router<Object>).first),
        ).read(appRouterProvider).go('/wallet');
        await pumpFrames(tester, frames: 8);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../../docs/screens/wallet_history/${state.key}-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
