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
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_accept_screen.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_transfer_screen.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../station_owner_fixtures.dart';

// Screen behaviour only. Signing and verification are covered end to end in
// data/services/station_owner_test.dart; widget tests under FakeAsync cannot
// await the real async crypto, so the service is faked here.

final _pops = PopCounter();
late String _toAddress;
late String _toPubkey;

String get _receiveCode =>
    ReceiveCode(address: _toAddress, pubkey: _toPubkey).encode();

const _station = 'mob-0123456789abcdef0123456789abcdef';
const _from = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

TransferOffer _offer() => TransferOffer(
  body: StationTransferBody(
    chainId: 'c-1',
    networkId: 'n-1',
    stationId: _station,
    fromOwnerAddress: _from,
    toOwnerAddress: _toAddress,
    toOwnerPubkey: _toPubkey,
    transferNonce: 3,
    expiresAtHeight: 6000,
  ),
  fromOwnerPubkey: 'b' * 64,
  fromOwnerSignature: 'd' * 128,
);

OwnerLedger _ledger() => OwnerLedger.fromJson(ledgerJson());

class _FakeService extends StationOwnerService {
  _FakeService()
    : super(api: FakeOwnerApi(ledgerJson()), openSession: () async => null);

  Completer<void>? gate;
  int beginCalls = 0;
  int startCalls = 0;
  int acceptCalls = 0;
  Object? startError;
  Object? beginError;
  Object? acceptError;
  TransferStatus status = TransferStatus.pendingConfirmation;
  int closes = 0;

  @override
  Future<TransferStarted> startTransfer(ReceiveCode to) async {
    startCalls++;
    if (gate != null) await gate!.future;
    if (startError != null) throw startError!;
    return TransferStarted(offer: _offer(), ledger: _ledger());
  }

  @override
  Future<ReceiveCode> myReceiveCode() async =>
      ReceiveCode(address: _toAddress, pubkey: _toPubkey);

  @override
  Future<AcceptFlow> beginAccept(String text) async {
    beginCalls++;
    if (gate != null) await gate!.future;
    if (beginError != null) throw beginError!;
    if (text == 'nope') throw const OfferRejected(OfferProblem.malformed);
    if (text == 'bad') throw const OfferRejected(OfferProblem.badSignature);
    return AcceptFlow(
      offer: _offer(),
      ledger: _ledger(),
      onAccept: () async {
        acceptCalls++;
        if (gate != null) await gate!.future;
        if (acceptError != null) throw acceptError!;
        return TransferSubmission(
          stationId: _station,
          toOwnerAddress: _toAddress,
          baselineNonce: 3,
          receipt: const OwnerSubmitReceipt(
            transactionIds: ['aa'],
            admissionHeight: 1,
          ),
        );
      },
      onClose: () => closes++,
    );
  }

  @override
  Future<TransferStatus> checkTransferApplied(TransferSubmission s) async =>
      status;

  @override
  Future<TransferStatus> checkApplied({
    required String stationId,
    required String toOwnerAddress,
    required int baselineNonce,
  }) async => status;
}

Future<void> _pump(WidgetTester tester, Widget screen, _FakeService svc) async {
  _pops.pops = 0;
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [stationOwnerServiceProvider.overrideWithValue(svc)],
      child: MaterialApp(home: screen, navigatorObservers: [_pops]),
    ),
  );
}

Future<void> _end(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

void main() {
  setUpAll(() async {
    final w = await ownerWallet(ownerSeedB);
    _toAddress = w.address;
    _toPubkey = w.pubkey;
  });

  group('StationTransferScreen', () {
    testWidgets('bad receive code is rejected; nothing is signed', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationTransferScreen(), svc);
      await t.enterText(find.byKey(const Key('receive-code-field')), 'junk');
      await t.tap(find.text('Review transfer'));
      await t.pump();
      expect(find.text('That is not a valid receive code.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(svc.startCalls, 0);
      await _end(t);
    });

    testWidgets('confirm dialog shows the FULL address; cancel signs nothing', (
      t,
    ) async {
      final svc = _FakeService();
      await _pump(t, const StationTransferScreen(), svc);
      await t.enterText(
        find.byKey(const Key('receive-code-field')),
        _receiveCode,
      );
      await t.tap(find.text('Review transfer'));
      await t.pump();
      expect(find.text('Give this station away?'), findsOneWidget);
      expect(find.text(_toAddress), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pump();
      expect(svc.startCalls, 0);
      expect(find.byType(QrImageView), findsNothing);
      await _end(t);
    });

    testWidgets('confirm shows offer QR + text, never claims done', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationTransferScreen(), svc);
      await t.enterText(
        find.byKey(const Key('receive-code-field')),
        _receiveCode,
      );
      await t.tap(find.text('Review transfer'));
      await t.pump();
      await t.tap(find.text('Sign transfer'));
      await _settle(t);
      expect(svc.startCalls, 1);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('not complete'), findsOneWidget);
      expect(find.textContaining('Transfer confirmed'), findsNothing);
      await _end(t);
    });

    testWidgets('check status: pending vs confirmed', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationTransferScreen(), svc);
      await t.enterText(
        find.byKey(const Key('receive-code-field')),
        _receiveCode,
      );
      await t.tap(find.text('Review transfer'));
      await t.pump();
      await t.tap(find.text('Sign transfer'));
      await _settle(t);
      await t.ensureVisible(find.text('Check status'));
      await t.tap(find.text('Check status'));
      await _settle(t);
      expect(find.textContaining('Waiting for the new owner'), findsOneWidget);
      expect(find.textContaining('Transfer confirmed'), findsNothing);
      svc.status = TransferStatus.confirmed;
      await t.tap(find.text('Check status'));
      await _settle(t);
      expect(find.textContaining('Transfer confirmed'), findsOneWidget);
      await _end(t);
    });

    testWidgets('a blocked station shows the reason, no QR', (t) async {
      final svc = _FakeService()
        ..startError = const StationOwnerBlocked(
          'The station is frozen. Unfreeze it before transferring.',
        );
      await _pump(t, const StationTransferScreen(), svc);
      await t.enterText(
        find.byKey(const Key('receive-code-field')),
        _receiveCode,
      );
      await t.tap(find.text('Review transfer'));
      await t.pump();
      await t.tap(find.text('Sign transfer'));
      await _settle(t);
      expect(find.textContaining('frozen'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      await _end(t);
    });

    testWidgets('a refusal shows fixed text, never the server message', (
      t,
    ) async {
      final svc = _FakeService()
        ..startError = const StationOwnerException(
          StationOwnerRefusal.featureNotActive,
        );
      await _pump(t, const StationTransferScreen(), svc);
      await t.enterText(
        find.byKey(const Key('receive-code-field')),
        _receiveCode,
      );
      await t.tap(find.text('Review transfer'));
      await t.pump();
      await t.tap(find.text('Sign transfer'));
      await _settle(t);
      expect(find.textContaining('not active on the network'), findsOneWidget);
      await _end(t);
    });

    testWidgets('biometric cancel says nothing was signed', (t) async {
      final svc = _FakeService()..startError = const StationOwnerCancelled();
      await _pump(t, const StationTransferScreen(), svc);
      await t.enterText(
        find.byKey(const Key('receive-code-field')),
        _receiveCode,
      );
      await t.tap(find.text('Review transfer'));
      await t.pump();
      await t.tap(find.text('Sign transfer'));
      await _settle(t);
      expect(find.text('Cancelled. Nothing was signed.'), findsOneWidget);
      await _end(t);
    });
  });

  group('StationAcceptScreen', () {
    testWidgets('shows my receive code as QR and text', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationAcceptScreen(), svc);
      await t.tap(find.text('Show my receive code'));
      await _settle(t);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining(_toAddress), findsOneWidget);
      expect(find.textContaining('WRFOWN1.receive.'), findsOneWidget);
      await _end(t);
    });

    testWidgets('a bad offer says do not accept; no accept button', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'bad');
      await t.tap(find.text('Review offer'));
      await _settle(t);
      expect(find.textContaining('Do not accept'), findsOneWidget);
      expect(find.text('Accept station'), findsNothing);
      await _end(t);
    });

    testWidgets('junk is rejected as not a transfer request', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'nope');
      await t.tap(find.text('Review offer'));
      await _settle(t);
      expect(
        find.textContaining('not a valid transfer request'),
        findsOneWidget,
      );
      await _end(t);
    });

    testWidgets('all fields shown; 201 is pending; confirmed only on ledger', (
      t,
    ) async {
      final svc = _FakeService();
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'ok');
      await t.tap(find.text('Review offer'));
      await _settle(t);
      expect(find.text(_station), findsOneWidget);
      expect(find.text(_from), findsOneWidget);
      expect(find.text(_toAddress), findsOneWidget);
      expect(find.text('6000'), findsOneWidget);
      expect(find.text('c-1 / n-1'), findsOneWidget);
      expect(find.textContaining('signature is valid'), findsOneWidget);
      expect(svc.acceptCalls, 0);

      await t.ensureVisible(find.text('Accept station'));
      await t.tap(find.text('Accept station'));
      await t.pump();
      expect(find.text('Take ownership of this station?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Accept station'));
      await _settle(t);
      expect(svc.acceptCalls, 1);
      expect(find.text('Pending confirmation'), findsOneWidget);
      expect(find.textContaining('You now own'), findsNothing);

      await t.tap(find.text('Check again'));
      await _settle(t);
      expect(find.text('Pending confirmation'), findsOneWidget);
      expect(find.textContaining('You now own'), findsNothing);

      svc.status = TransferStatus.unknown;
      await t.tap(find.text('Check again'));
      await _settle(t);
      expect(find.textContaining('Status unavailable'), findsOneWidget);
      expect(find.textContaining('You now own'), findsNothing);

      svc.status = TransferStatus.confirmed;
      await t.tap(find.text('Check again'));
      await _settle(t);
      expect(find.textContaining('You now own this station'), findsOneWidget);
      await _end(t);
    });

    testWidgets('cancelling the confirm dialog submits nothing', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'ok');
      await t.tap(find.text('Review offer'));
      await _settle(t);
      await t.ensureVisible(find.text('Accept station'));
      await t.tap(find.text('Accept station'));
      await t.pump();
      await t.tap(find.text('Cancel'));
      await t.pump();
      expect(svc.acceptCalls, 0);
      await _end(t);
    });

    testWidgets('a 422 refusal shows fixed text and never pending', (t) async {
      final svc = _FakeService()
        ..acceptError = const StationOwnerException(
          StationOwnerRefusal.nonceMismatch,
          code: 'OWNER_TX_NONCE_MISMATCH',
        );
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'ok');
      await t.tap(find.text('Review offer'));
      await _settle(t);
      await t.ensureVisible(find.text('Accept station'));
      await t.tap(find.text('Accept station'));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Accept station'));
      await _settle(t);
      expect(find.textContaining('changed since this request'), findsOneWidget);
      expect(find.text('Pending confirmation'), findsNothing);
      await _end(t);
    });

    testWidgets('an uncertain 201 says check status, never "not accepted"', (
      t,
    ) async {
      final svc = _FakeService()
        ..acceptError = const StationOwnerException(
          StationOwnerRefusal.uncertain,
        );
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'ok');
      await t.tap(find.text('Review offer'));
      await _settle(t);
      await t.ensureVisible(find.text('Accept station'));
      await t.tap(find.text('Accept station'));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Accept station'));
      await _settle(t);
      expect(find.textContaining('could not tell whether'), findsOneWidget);
      expect(find.textContaining('did not accept'), findsNothing);
      expect(find.text('Pending confirmation'), findsNothing);
    });

    testWidgets('leaving the screen closes the signing session', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'ok');
      await t.tap(find.text('Review offer'));
      await _settle(t);
      await _end(t);
      expect(svc.closes, greaterThanOrEqualTo(1));
    });
  });

  group('a double tap never starts two operations', () {
    // Two taps land in the same frame (no pump between them).
    testWidgets('transfer review: one dialog', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationTransferScreen(), svc);
      await t.enterText(
        find.byKey(const Key('receive-code-field')),
        _receiveCode,
      );
      final before = _pops.pushes;
      invokeTwice(t, find.widgetWithText(ElevatedButton, 'Review transfer'));
      await t.pump();
      expect(_pops.pushes - before, 1, reason: 'one dialog route');
      expect(find.text('Give this station away?'), findsOneWidget);
      await _end(t);
    });

    testWidgets('transfer confirm: one signing, one pop', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationTransferScreen(), svc);
      await t.enterText(
        find.byKey(const Key('receive-code-field')),
        _receiveCode,
      );
      await t.tap(find.text('Review transfer'));
      await t.pump();
      svc.gate = Completer<void>();
      final before = _pops.pops;
      invokeTwice(t, find.widgetWithText(FilledButton, 'Sign transfer'));
      await t.pump();
      await t.pump();
      expect(svc.startCalls, 1);
      expect(_pops.pops - before, 1);
      svc.gate!.complete();
      await _settle(t);
      expect(svc.startCalls, 1);
      await _end(t);
    });

    testWidgets('accept review: one review while it runs', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'ok');
      svc.gate = Completer<void>();
      invokeTwice(t, find.widgetWithText(ElevatedButton, 'Review offer'));
      await t.pump();
      expect(svc.beginCalls, 1);
      svc.gate!.complete();
      await _settle(t);
      expect(svc.beginCalls, 1);
      await _end(t);
    });

    testWidgets('accept: one dialog', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'ok');
      await t.tap(find.text('Review offer'));
      await _settle(t);
      await t.ensureVisible(find.text('Accept station'));
      final before = _pops.pushes;
      invokeTwice(t, find.widgetWithText(ElevatedButton, 'Accept station'));
      await t.pump();
      expect(_pops.pushes - before, 1, reason: 'one dialog route');
      expect(find.text('Take ownership of this station?'), findsOneWidget);
      await _end(t);
    });

    testWidgets('accept confirm: one accept, one pop', (t) async {
      final svc = _FakeService();
      await _pump(t, const StationAcceptScreen(), svc);
      await t.enterText(find.byKey(const Key('offer-field')), 'ok');
      await t.tap(find.text('Review offer'));
      await _settle(t);
      await t.ensureVisible(find.text('Accept station'));
      await t.tap(find.text('Accept station'));
      await t.pump();
      svc.gate = Completer<void>();
      final before = _pops.pops;
      final confirm = find.widgetWithText(FilledButton, 'Accept station');
      invokeTwice(t, confirm);
      await t.pump();
      await t.pump();
      expect(svc.acceptCalls, 1);
      expect(_pops.pops - before, 1);
      svc.gate!.complete();
      await _settle(t);
      expect(svc.acceptCalls, 1);
      await _end(t);
    });
  });
}
