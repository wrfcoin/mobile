import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_exchange.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_service.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/station_owner_providers.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_recovery_screen.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../station_owner_fixtures.dart';

const _station = 'mob-0123456789abcdef0123456789abcdef';
const _from = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
late String _to;
late String _pub;

StationRecoveryBody _body() => StationRecoveryBody(
  chainId: 'c-1',
  networkId: 'n-1',
  stationId: _station,
  fromOwnerAddress: _from,
  toOwnerAddress: _to,
  toOwnerPubkey: _pub,
  recoveryNonce: 3,
);

final _pops = PopCounter();

class _FakeService extends StationOwnerService {
  _FakeService()
    : super(api: FakeOwnerApi(ledgerJson()), openSession: () async => null);

  Completer<void>? gate;
  int beginCalls = 0;
  int countersigns = 0;
  int executes = 0;
  Object? executeError;
  TransferStatus status = TransferStatus.pendingConfirmation;
  int closes = 0;

  @override
  Future<RecoveryAcceptFlow> beginRecoveryAccept(String text) async {
    beginCalls++;
    if (gate != null) await gate!.future;
    if (text == 'nope') throw const OfferRejected(OfferProblem.malformed);
    if (text == 'moved') throw const OfferRejected(OfferProblem.nonceMismatch);
    return RecoveryAcceptFlow(
      request: RecoveryRequest(body: _body()),
      ledger: OwnerLedger.fromJson(ledgerJson()),
      onCountersign: () async {
        countersigns++;
        if (gate != null) await gate!.future;
        return RecoveryAcceptText(
          body: _body(),
          toOwnerSignature: 'd' * 128,
        ).encode();
      },
      onClose: () => closes++,
    );
  }

  @override
  Future<RecoveryExecuteSubmission> executeRecovery(String stationId) async {
    executes++;
    if (gate != null) await gate!.future;
    if (executeError != null) throw executeError!;
    return RecoveryExecuteSubmission(
      stationId: stationId,
      toOwnerCommitment: 'a' * 64,
      baselineNonce: 3,
      receipt: const OwnerSubmitReceipt(
        transactionIds: ['aa'],
        admissionHeight: 1,
      ),
    );
  }

  @override
  Future<TransferStatus> checkRecoveryExecuted(
    RecoveryExecuteSubmission s,
  ) async => status;
}

Future<void> _pump(WidgetTester t, _FakeService svc) async {
  _pops.pops = 0;
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [stationOwnerServiceProvider.overrideWithValue(svc)],
      child: MaterialApp(
        home: const StationRecoveryScreen(),
        navigatorObservers: [_pops],
      ),
    ),
  );
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

Future<void> _review(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('recovery-field')), text);
  await t.tap(find.text('Review recovery request'));
  await _settle(t);
}

void main() {
  setUpAll(() async {
    final w = await ownerWallet(ownerSeedB);
    _to = w.address;
    _pub = w.pubkey;
  });

  testWidgets('junk and a moved station are refused before any signing', (
    t,
  ) async {
    final svc = _FakeService();
    await _pump(t, svc);
    await _review(t, 'nope');
    expect(find.textContaining('not a valid transfer request'), findsOneWidget);
    await _review(t, 'moved');
    expect(find.textContaining('changed since'), findsOneWidget);
    expect(find.text('Countersign'), findsNothing);
    expect(svc.countersigns, 0);
  });

  testWidgets('every field is shown with a security warning', (t) async {
    await _pump(t, _FakeService());
    await _review(t, 'ok');
    expect(find.text(_station), findsOneWidget);
    expect(find.text(_from), findsOneWidget);
    expect(find.text(_to), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('c-1 / n-1'), findsOneWidget);
    expect(find.textContaining('Only countersign if'), findsOneWidget);
  });

  testWidgets('countersign returns text + QR for the operator, no submit', (
    t,
  ) async {
    final svc = _FakeService();
    await _pump(t, svc);
    await _review(t, 'ok');
    await t.ensureVisible(find.text('Countersign'));
    await t.tap(find.text('Countersign'));
    await t.pump();
    expect(find.text('Countersign this recovery?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Countersign'));
    await _settle(t);
    expect(svc.countersigns, 1);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('WRFOWN1.recovery-accept.'), findsOneWidget);
    expect(
      find.textContaining('Give this back to the operator'),
      findsOneWidget,
    );
    expect(find.textContaining('Recovery complete'), findsNothing);
  });

  testWidgets('cancelling the dialog countersigns nothing', (t) async {
    final svc = _FakeService();
    await _pump(t, svc);
    await _review(t, 'ok');
    await t.ensureVisible(find.text('Countersign'));
    await t.tap(find.text('Countersign'));
    await t.pump();
    await t.tap(find.text('Cancel'));
    await t.pump();
    expect(svc.countersigns, 0);
  });

  testWidgets('complete recovery: blocked reason, then pending, then done', (
    t,
  ) async {
    final svc = _FakeService()
      ..executeError = const StationOwnerBlocked(
        'This recovery can be completed in about 3 days (estimate).',
      );
    await _pump(t, svc);
    await t.enterText(find.byKey(const Key('station-id-field')), _station);
    await t.ensureVisible(find.text('Complete recovery'));
    await t.tap(find.text('Complete recovery'));
    await _settle(t);
    expect(find.textContaining('about 3 days (estimate)'), findsOneWidget);
    expect(find.text('Pending confirmation'), findsNothing);

    svc.executeError = null;
    await t.tap(find.text('Complete recovery'));
    await _settle(t);
    expect(find.text('Pending confirmation'), findsOneWidget);
    expect(find.textContaining('Recovery complete'), findsNothing);
    await t.tap(find.text('Check again'));
    await _settle(t);
    expect(find.text('Pending confirmation'), findsOneWidget);
    svc.status = TransferStatus.confirmed;
    await t.tap(find.text('Check again'));
    await _settle(t);
    expect(find.textContaining('Recovery complete'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('leaving closes the signing session', (t) async {
    final svc = _FakeService();
    await _pump(t, svc);
    await _review(t, 'ok');
    await t.pumpWidget(const SizedBox());
    expect(svc.closes, greaterThanOrEqualTo(1));
  });

  group('a double tap never starts two operations', () {
    // Two taps land in the same frame (no pump between them).
    testWidgets('review: one review while it runs', (t) async {
      final svc = _FakeService();
      await _pump(t, svc);
      await t.enterText(find.byKey(const Key('recovery-field')), 'ok');
      svc.gate = Completer<void>();
      invokeTwice(
        t,
        find.widgetWithText(ElevatedButton, 'Review recovery request'),
      );
      await t.pump();
      expect(svc.beginCalls, 1);
      svc.gate!.complete();
      await _settle(t);
      expect(svc.beginCalls, 1);
    });

    testWidgets('countersign: one dialog', (t) async {
      final svc = _FakeService();
      await _pump(t, svc);
      await _review(t, 'ok');
      await t.ensureVisible(find.text('Countersign'));
      final before = _pops.pushes;
      invokeTwice(t, find.widgetWithText(ElevatedButton, 'Countersign'));
      await t.pump();
      expect(_pops.pushes - before, 1, reason: 'one dialog route');
      expect(find.text('Countersign this recovery?'), findsOneWidget);
    });

    testWidgets('countersign confirm: one signing, one pop', (t) async {
      final svc = _FakeService();
      await _pump(t, svc);
      await _review(t, 'ok');
      await t.ensureVisible(find.text('Countersign'));
      await t.tap(find.text('Countersign'));
      await t.pump();
      svc.gate = Completer<void>();
      final before = _pops.pops;
      final confirm = find.widgetWithText(FilledButton, 'Countersign');
      invokeTwice(t, confirm);
      await t.pump();
      await t.pump();
      expect(svc.countersigns, 1);
      expect(_pops.pops - before, 1);
      svc.gate!.complete();
      await _settle(t);
      expect(svc.countersigns, 1);
    });

    testWidgets('complete recovery: one submit', (t) async {
      final svc = _FakeService();
      await _pump(t, svc);
      await t.enterText(find.byKey(const Key('station-id-field')), _station);
      await t.ensureVisible(find.text('Complete recovery'));
      svc.gate = Completer<void>();
      invokeTwice(t, find.widgetWithText(OutlinedButton, 'Complete recovery'));
      await t.pump();
      expect(svc.executes, 1);
      svc.gate!.complete();
      await _settle(t);
      expect(svc.executes, 1);
    });
  });
}
