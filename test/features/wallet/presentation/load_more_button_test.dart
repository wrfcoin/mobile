import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';

import '../../../test_helpers/app_harness.dart';
import '../../../test_helpers/screenshot_fonts.dart';

class _Fixed extends TransactionsNotifier {
  _Fixed(this.fixed);
  final TransactionsState fixed;

  @override
  Future<TransactionsState> build() async => fixed;
}

void main() {
  Future<void> pump(WidgetTester tester, TransactionsState state) async {
    // The default test font is too wide for the Wallet tab at 390 px.
    await loadFlutterCacheFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
    SharedPreferences.setMockInitialValues({'welcome.seen': true});
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = createTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
        signedIn: true,
        extraOverrides: [
          transactionsProvider.overrideWith(() => _Fixed(state)),
        ],
      ),
    );
    await pumpFrames(tester);
    ProviderScope.containerOf(tester.element(find.byType(Router<Object>).first))
        .read(appRouterProvider)
        .go('/wallet');
    await pumpFrames(tester, frames: 8);
  }

  OutlinedButton button(WidgetTester tester) =>
      tester.widget<OutlinedButton>(find.byKey(const Key('wallet-load-more')));

  testWidgets('while loading it says so and can\'t be tapped', (tester) async {
    await pump(
      tester,
      const TransactionsState(items: [], hasMore: true, loadingMore: true),
    );
    expect(find.byKey(const Key('wallet-load-more-busy')), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);
    expect(button(tester).onPressed, isNull);
  });

  testWidgets('at rest it can be tapped', (tester) async {
    await pump(
      tester,
      const TransactionsState(items: [], hasMore: true, loadingMore: false),
    );
    expect(find.text('Load more'), findsOneWidget);
    expect(button(tester).onPressed, isNotNull);
  });

  testWidgets('a tap that found nothing says so', (tester) async {
    await pump(
      tester,
      const TransactionsState(
        items: [],
        hasMore: true,
        loadingMore: false,
        lastLoadFoundNothing: true,
      ),
    );
    expect(find.byKey(const Key('wallet-load-more-nothing')), findsOneWidget);
  });

  testWidgets('a tap that failed says so', (tester) async {
    await pump(
      tester,
      const TransactionsState(
        items: [],
        hasMore: true,
        loadingMore: false,
        lastLoadFailed: true,
      ),
    );
    expect(find.byKey(const Key('wallet-load-more-failed')), findsOneWidget);
    expect(button(tester).onPressed, isNotNull);
  });
}
