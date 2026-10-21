import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_service.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/station_owner_providers.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_security_screen.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../station_owner_fixtures.dart';

final _pops = PopCounter();

class _FakeService extends StationOwnerService {
  _FakeService()
    : super(api: FakeOwnerApi(ledgerJson()), openSession: () async => null);

  Completer<void>? gate;
  int performs = 0;
  StationOwnerAction? lastAction;
  Object? performError;
  TransferStatus status = TransferStatus.pendingConfirmation;

  @override
  Future<OwnerActionSubmission> performOwnerAction(
    StationOwnerAction action,
  ) async {
    performs++;
    if (gate != null) await gate!.future;
    lastAction = action;
    if (performError != null) throw performError!;
    return OwnerActionSubmission(
      stationId: 'st',
      action: action,
      baselineNonce: 3,
      receipt: const OwnerSubmitReceipt(
        transactionIds: ['aa'],
        admissionHeight: 1,
      ),
    );
  }

  int cancels = 0;
  Object? cancelError;
  TransferStatus cancelStatus = TransferStatus.pendingConfirmation;

  @override
  Future<RecoveryCancelSubmission> cancelRecovery() async {
    cancels++;
    if (gate != null) await gate!.future;
    if (cancelError != null) throw cancelError!;
    return const RecoveryCancelSubmission(
      stationId: 'st',
      baselineNonce: 3,
      receipt: OwnerSubmitReceipt(transactionIds: ['aa'], admissionHeight: 1),
    );
  }

  @override
  Future<TransferStatus> checkRecoveryCancelled(
    RecoveryCancelSubmission s,
  ) async => cancelStatus;

  @override
  Future<TransferStatus> checkActionApplied(OwnerActionSubmission s) async =>
      status;
}

Future<void> _pump(
  WidgetTester t,
  _FakeService svc, {
  Map<String, dynamic>? ledger,
  bool ledgerFails = false,
}) async {
  _pops.pops = 0;
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        stationOwnerServiceProvider.overrideWithValue(svc),
        ownerStationLedgerProvider.overrideWith((ref) async {
          if (ledgerFails) {
            throw const StationOwnerException(StationOwnerRefusal.unavailable);
          }
          return OwnerLedger.fromJson(ledger ?? ledgerJson());
        }),
      ],
      child: MaterialApp(
        home: const StationSecurityScreen(),
        navigatorObservers: [_pops],
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('normal station offers Report stolen and Deactivate only', (
    t,
  ) async {
    await _pump(t, _FakeService());
    expect(find.text('Your station is active.'), findsOneWidget);
    expect(find.text('Report stolen'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
    expect(find.text('Unfreeze'), findsNothing);
    expect(find.text('Reactivate'), findsNothing);
  });

  group('per-state actions and confirm copy', () {
    final cases =
        <
          String,
          ({
            Map<String, dynamic> ledger,
            String button,
            String title,
            String warn,
            String yes,
            StationOwnerAction action,
            String done,
          })
        >{
          'unfreeze': (
            ledger: ledgerJson(frozen: {'since_height': 55}),
            button: 'Unfreeze',
            title: 'Unfreeze this station?',
            warn: 'back in your hands',
            yes: 'Unfreeze station',
            action: StationOwnerAction.unfreeze,
            done: 'Station unfrozen',
          ),
          'deactivate': (
            ledger: ledgerJson(),
            button: 'Deactivate',
            title: 'Deactivate this station?',
            warn: 'stops earning until you reactivate',
            yes: 'Deactivate station',
            action: StationOwnerAction.deactivate,
            done: 'Station deactivated',
          ),
          'reactivate': (
            ledger: ledgerJson(deactivated: true),
            button: 'Reactivate',
            title: 'Reactivate this station?',
            warn: 'resume earning',
            yes: 'Reactivate station',
            action: StationOwnerAction.reactivate,
            done: 'Station reactivated',
          ),
        };
    for (final e in cases.entries) {
      testWidgets('${e.key}: warns, cancel signs nothing', (t) async {
        final svc = _FakeService();
        await _pump(t, svc, ledger: e.value.ledger);
        await t.tap(find.text(e.value.button));
        await t.pump();
        expect(find.text(e.value.title), findsOneWidget);
        expect(find.textContaining(e.value.warn), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pump();
        expect(svc.performs, 0);
      });

      testWidgets('${e.key}: pending until the ledger shows it', (t) async {
        final svc = _FakeService();
        await _pump(t, svc, ledger: e.value.ledger);
        await t.tap(find.text(e.value.button));
        await t.pump();
        await t.tap(find.widgetWithText(FilledButton, e.value.yes));
        await _settle(t);
        expect(svc.lastAction, e.value.action);
        expect(find.text('Pending confirmation'), findsOneWidget);
        expect(find.textContaining(e.value.done), findsNothing);
        svc.status = TransferStatus.confirmed;
        await t.tap(find.text('Check again'));
        await _settle(t);
        expect(find.textContaining(e.value.done), findsOneWidget);
        expect(find.text('Pending confirmation'), findsNothing);
      });
    }

    testWidgets('a frozen station offers only Unfreeze', (t) async {
      await _pump(
        t,
        _FakeService(),
        ledger: ledgerJson(frozen: {'since_height': 1}),
      );
      expect(find.text('Unfreeze'), findsOneWidget);
      expect(find.text('Report stolen'), findsNothing);
      expect(find.text('Deactivate'), findsNothing);
      expect(find.text('Reactivate'), findsNothing);
    });

    testWidgets('a deactivated station offers Reactivate and Report stolen', (
      t,
    ) async {
      await _pump(t, _FakeService(), ledger: ledgerJson(deactivated: true));
      expect(find.text('Reactivate'), findsOneWidget);
      expect(find.text('Report stolen'), findsOneWidget);
      expect(find.text('Deactivate'), findsNothing);
    });
  });

  testWidgets('a failed read is "unavailable" with Retry, never "active"', (
    t,
  ) async {
    await _pump(t, _FakeService(), ledgerFails: true);
    expect(find.textContaining('unavailable right now'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Your station is active.'), findsNothing);
    expect(find.text('Report stolen'), findsNothing);
  });

  testWidgets('inactive network feature disables the action with a reason', (
    t,
  ) async {
    await _pump(t, _FakeService(), ledger: ledgerJson(actions: false));
    expect(
      find.textContaining('not active on the network yet'),
      findsOneWidget,
    );
    expect(find.text('Report stolen'), findsNothing);
  });

  testWidgets('a frozen station shows frozen and cannot be frozen again', (
    t,
  ) async {
    await _pump(
      t,
      _FakeService(),
      ledger: ledgerJson(frozen: {'since_height': 55}),
    );
    expect(find.textContaining('Frozen since block 55'), findsOneWidget);
    expect(find.text('Report stolen'), findsNothing);
    expect(find.text('Your station is active.'), findsNothing);
  });

  testWidgets('confirm dialog warns; cancel signs nothing', (t) async {
    final svc = _FakeService();
    await _pump(t, svc);
    await t.tap(find.text('Report stolen'));
    await t.pump();
    expect(find.text('Freeze this station?'), findsOneWidget);
    expect(
      find.textContaining('Only do this if the device is lost'),
      findsOneWidget,
    );
    await t.tap(find.text('Cancel'));
    await t.pump();
    expect(svc.performs, 0);
  });

  testWidgets('confirm submits; 201 is pending; applied only on ledger', (
    t,
  ) async {
    final svc = _FakeService();
    await _pump(t, svc);
    await t.tap(find.text('Report stolen'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Freeze station'));
    await _settle(t);
    expect(svc.performs, 1);
    expect(find.text('Pending confirmation'), findsOneWidget);
    expect(find.textContaining('Station frozen'), findsNothing);

    await t.tap(find.text('Check again'));
    await _settle(t);
    expect(find.text('Pending confirmation'), findsOneWidget);

    svc.status = TransferStatus.unknown;
    await t.tap(find.text('Check again'));
    await _settle(t);
    expect(find.textContaining('Status unavailable'), findsOneWidget);
    expect(find.textContaining('Station frozen'), findsNothing);

    svc.status = TransferStatus.confirmed;
    await t.tap(find.text('Check again'));
    await _settle(t);
    expect(find.textContaining('Station frozen'), findsOneWidget);
    expect(find.text('Pending confirmation'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('refusals show fixed text and never pending', (t) async {
    final svc = _FakeService()
      ..performError = const StationOwnerException(
        StationOwnerRefusal.nonceMismatch,
        code: 'OWNER_TX_NONCE_MISMATCH',
      );
    await _pump(t, svc);
    await t.tap(find.text('Report stolen'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Freeze station'));
    await _settle(t);
    expect(find.textContaining('changed since this request'), findsOneWidget);
    expect(find.text('Pending confirmation'), findsNothing);
  });

  testWidgets('biometric cancel says nothing was signed', (t) async {
    final svc = _FakeService()..performError = const StationOwnerCancelled();
    await _pump(t, svc);
    await t.tap(find.text('Report stolen'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Freeze station'));
    await _settle(t);
    expect(find.text('Cancelled. Nothing was signed.'), findsOneWidget);
  });

  group('pending recovery banner and cancel', () {
    Map<String, dynamic> withPending({int observed = 1000}) => ledgerJson(
      observed: observed,
      pending: {
        'from_owner_address': '0xa',
        'to_owner_address': '0xb',
        'recovery_nonce': 3,
        'filed_at_height': 900,
        'executable_at_height': 34900,
      },
    );

    testWidgets('banner warns, shows height and a labelled estimate', (
      t,
    ) async {
      await _pump(t, _FakeService(), ledger: withPending());
      expect(
        find.textContaining('Someone has asked to take over this station'),
        findsOneWidget,
      );
      expect(
        find.textContaining("If this wasn't you, cancel now"),
        findsOneWidget,
      );
      expect(find.textContaining('block 34900'), findsOneWidget);
      expect(find.textContaining('estimate'), findsOneWidget);
      expect(find.text('Cancel recovery'), findsOneWidget);
      // a station with a pending recovery is not "active and fine"
      expect(find.text('Your station is active.'), findsNothing);
    });

    testWidgets('no banner when nothing is pending', (t) async {
      await _pump(t, _FakeService());
      expect(find.textContaining('Someone has asked'), findsNothing);
      expect(find.text('Cancel recovery'), findsNothing);
    });

    testWidgets('closed window: no cancel button, says so', (t) async {
      await _pump(t, _FakeService(), ledger: withPending(observed: 34899));
      expect(find.text('Cancel recovery'), findsNothing);
      expect(
        find.textContaining('window to cancel has closed'),
        findsOneWidget,
      );
    });

    testWidgets('cancel dialog warns; not now signs nothing', (t) async {
      final svc = _FakeService();
      await _pump(t, svc, ledger: withPending());
      await t.tap(find.text('Cancel recovery'));
      await t.pump();
      expect(find.text('Cancel this recovery?'), findsOneWidget);
      expect(find.textContaining('did NOT start it'), findsOneWidget);
      await t.tap(find.text('Not now'));
      await t.pump();
      expect(svc.cancels, 0);
    });

    testWidgets('cancel: pending until the ledger shows it', (t) async {
      final svc = _FakeService();
      await _pump(t, svc, ledger: withPending());
      await t.tap(find.text('Cancel recovery'));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Cancel recovery'));
      await _settle(t);
      expect(svc.cancels, 1);
      expect(find.text('Pending confirmation'), findsOneWidget);
      expect(find.textContaining('Recovery cancelled'), findsNothing);
      await t.tap(find.text('Check again'));
      await _settle(t);
      expect(find.textContaining('Recovery cancelled'), findsNothing);
      svc.cancelStatus = TransferStatus.confirmed;
      await t.tap(find.text('Check again'));
      await _settle(t);
      expect(find.textContaining('Recovery cancelled'), findsOneWidget);
    });

    testWidgets('cancel refusal shows fixed text, never pending', (t) async {
      final svc = _FakeService()
        ..cancelError = const StationOwnerException(
          StationOwnerRefusal.noticeWindowElapsed,
          code: 'OWNER_TX_NOTICE_WINDOW_ELAPSED',
        );
      await _pump(t, svc, ledger: withPending());
      await t.tap(find.text('Cancel recovery'));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Cancel recovery'));
      await _settle(t);
      expect(
        find.textContaining('window to cancel this recovery'),
        findsOneWidget,
      );
      expect(find.text('Pending confirmation'), findsNothing);
    });
  });

  group('a double tap never starts two operations', () {
    // Two taps land in the same frame (no pump between them).
    final pendingLedger = ledgerJson(
      pending: {
        'from_owner_address': '0xa',
        'to_owner_address': '0xb',
        'recovery_nonce': 3,
        'filed_at_height': 900,
        'executable_at_height': 34900,
      },
    );
    final cases =
        <
          String,
          ({
            Map<String, dynamic> ledger,
            String button,
            String title,
            String yes,
            bool isCancel,
          })
        >{
          'report stolen': (
            ledger: ledgerJson(),
            button: 'Report stolen',
            title: 'Freeze this station?',
            yes: 'Freeze station',
            isCancel: false,
          ),
          'unfreeze': (
            ledger: ledgerJson(frozen: {'since_height': 55}),
            button: 'Unfreeze',
            title: 'Unfreeze this station?',
            yes: 'Unfreeze station',
            isCancel: false,
          ),
          'deactivate': (
            ledger: ledgerJson(),
            button: 'Deactivate',
            title: 'Deactivate this station?',
            yes: 'Deactivate station',
            isCancel: false,
          ),
          'reactivate': (
            ledger: ledgerJson(deactivated: true),
            button: 'Reactivate',
            title: 'Reactivate this station?',
            yes: 'Reactivate station',
            isCancel: false,
          ),
          'cancel recovery': (
            ledger: pendingLedger,
            button: 'Cancel recovery',
            title: 'Cancel this recovery?',
            yes: 'Cancel recovery',
            isCancel: true,
          ),
        };
    for (final e in cases.entries) {
      testWidgets('${e.key}: one dialog', (t) async {
        final svc = _FakeService();
        await _pump(t, svc, ledger: e.value.ledger);
        final before = _pops.pushes;
        invokeTwice(t, find.widgetWithText(ElevatedButton, e.value.button));
        await t.pump();
        expect(_pops.pushes - before, 1, reason: 'one dialog route');
        expect(find.text(e.value.title), findsOneWidget);
      });

      testWidgets('${e.key}: one submit, one pop', (t) async {
        final svc = _FakeService();
        await _pump(t, svc, ledger: e.value.ledger);
        await t.tap(find.text(e.value.button));
        await t.pump();
        svc.gate = Completer<void>();
        final before = _pops.pops;
        final confirm = find.widgetWithText(FilledButton, e.value.yes);
        invokeTwice(t, confirm);
        await t.pump();
        await t.pump();
        expect(e.value.isCancel ? svc.cancels : svc.performs, 1);
        expect(_pops.pops - before, 1);
        svc.gate!.complete();
        await _settle(t);
        expect(e.value.isCancel ? svc.cancels : svc.performs, 1);
      });
    }
  });
}
