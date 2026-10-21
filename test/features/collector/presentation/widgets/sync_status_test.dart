import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/sync_status.dart';

void main() {
  testWidgets('shows synced state with semantics label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SyncStatus(pendingCount: 0))),
    );

    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('shows pending state with semantics label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SyncStatus(pendingCount: 4))),
    );

    expect(find.text('4 pending'), findsOneWidget);
  });
}
