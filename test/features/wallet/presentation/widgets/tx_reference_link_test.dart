import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/tx_reference_link.dart';

void main() {
  final hash = '0x${'ab' * 32}';

  Future<List<(Uri, LaunchMode)>> pump(
    WidgetTester tester, {
    required bool Function(LaunchMode mode) opens,
  }) async {
    final calls = <(Uri, LaunchMode)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TxReferenceLink(
            hash: hash,
            launch: (url, {mode = LaunchMode.platformDefault}) async {
              calls.add((url, mode));
              return opens(mode);
            },
          ),
        ),
      ),
    );
    return calls;
  }

  test('points at the website transaction page', () {
    expect(
      websiteTxPage(hash).toString(),
      'https://wrfcoin.com/explore/tx/$hash',
    );
  });

  testWidgets('tapping the reference opens its page in the app browser', (
    tester,
  ) async {
    final calls = await pump(tester, opens: (_) => true);
    expect(find.text(hash), findsOneWidget);
    expect(
      find.text(
        'Tap to see it on wrfcoin.com. It can take about a minute to show in '
        'a block.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('tx-reference-link')));
    await tester.pumpAndSettle();
    expect(calls, [(websiteTxPage(hash), LaunchMode.inAppBrowserView)]);
  });

  testWidgets('falls back to the browser, then says it could not open', (
    tester,
  ) async {
    final calls = await pump(tester, opens: (_) => false);
    await tester.tap(find.byKey(const Key('tx-reference-link')));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.$2), [
      LaunchMode.inAppBrowserView,
      LaunchMode.externalApplication,
    ]);
    expect(find.text("Couldn't open the transaction page."), findsOneWidget);
  });
}
