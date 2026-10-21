import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/station_owner_providers.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/owner_ledger_banner.dart';

import '../station_owner_fixtures.dart';

Future<void> _pump(WidgetTester t, Future<OwnerLedger> Function() read) async {
  await t.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [ownerStationLedgerProvider.overrideWith((ref) => read())],
      child: const MaterialApp(home: Scaffold(body: OwnerLedgerBanner())),
    ),
  );
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('a failed read shows a neutral Status unavailable chip', (
    t,
  ) async {
    await _pump(
      t,
      () async =>
          throw const StationOwnerException(StationOwnerRefusal.unavailable),
    );
    expect(find.text('Status unavailable'), findsOneWidget);
    // neutral: never claims anything about the station
    expect(find.textContaining('frozen'), findsNothing);
    expect(find.textContaining('Someone has asked'), findsNothing);
    expect(find.textContaining('active'), findsNothing);
  });

  testWidgets('loading shows nothing', (t) async {
    final never = Completer<OwnerLedger>();
    await _pump(t, () => never.future);
    expect(find.text('Status unavailable'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('a clean ledger shows nothing', (t) async {
    await _pump(t, () async => OwnerLedger.fromJson(ledgerJson()));
    expect(find.text('Status unavailable'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('pending recovery and frozen are shown from the ledger', (
    t,
  ) async {
    await _pump(
      t,
      () async => OwnerLedger.fromJson(
        ledgerJson(
          frozen: {'since_height': 55},
          pending: {
            'from_owner_address': '0xa',
            'to_owner_address': '0xb',
            'recovery_nonce': 3,
            'filed_at_height': 900,
            'executable_at_height': 34900,
          },
        ),
      ),
    );
    expect(
      find.textContaining('Someone has asked to take over'),
      findsOneWidget,
    );
    expect(find.textContaining('frozen since block 55'), findsOneWidget);
    expect(find.text('Status unavailable'), findsNothing);
  });
}
