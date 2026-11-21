// Widget tests for the "Phone that sends readings" section of the security
// screen. The screenshot tests are skipped unless SCREENSHOT_FONT_DIR is set:
//   SCREENSHOT_FONT_DIR=$FLUTTER/bin/cache/artifacts/material_fonts \
//     flutter test --update-goldens \
//     test/features/collector/presentation/station_submitter_section_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_service.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/station_owner_providers.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_security_screen.dart';

import '../../../test_helpers/screenshot_fonts.dart';
import '../station_owner_fixtures.dart';

final _mine = 'c4' * 32;
final _other = 'd5' * 32;

class _Svc extends StationOwnerService {
  _Svc()
    : super(api: FakeOwnerApi(ledgerJson()), openSession: () async => null);

  final List<bool> calls = [];
  TransferStatus status = TransferStatus.pendingConfirmation;

  SubmitterKeySubmission _sub(String? key) => SubmitterKeySubmission(
    stationId: 'st',
    submitterPubkey: key,
    baselineNonce: 3,
    receipt: const OwnerSubmitReceipt(
      transactionIds: ['aa'],
      admissionHeight: 1,
    ),
  );

  @override
  Future<SubmitterKeySubmission> approveThisPhoneAsSubmitter() async {
    calls.add(true);
    return _sub(_mine);
  }

  @override
  Future<SubmitterKeySubmission> clearSubmitterKey() async {
    calls.add(false);
    return _sub(null);
  }

  @override
  Future<TransferStatus> checkSubmitterApplied(
    SubmitterKeySubmission s,
  ) async => status;
}

Map<String, dynamic> _ledger({
  bool? active,
  Object? submitter = const _Absent(),
  Object? frozen,
}) {
  final j = ledgerJson(frozen: frozen);
  if (active != null) {
    j['features'] = <String, Object>{
      ...(j['features'] as Map<String, dynamic>),
      'stationSubmitterKey': active,
    };
  }
  if (submitter is! _Absent) j['submitterKey'] = submitter;
  return j;
}

class _Absent {
  const _Absent();
}

Future<void> _pump(
  WidgetTester t,
  _Svc svc,
  Map<String, dynamic> ledger, {
  String? phoneKey,
  Size size = const Size(900, 2400),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        stationOwnerServiceProvider.overrideWithValue(svc),
        ownerStationLedgerProvider.overrideWith(
          (ref) async => OwnerLedger.fromJson(ledger),
        ),
        thisPhoneCollectPubkeyProvider.overrideWith((ref) async => phoneKey),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: StationSecurityScreen(),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('inert today: no flag reported -> plain text, no buttons', (
    t,
  ) async {
    await _pump(t, _Svc(), ledgerJson(), phoneKey: _mine);
    expect(find.text('Phone that sends readings'), findsOneWidget);
    expect(
      find.text(
        'Approving this phone to send readings is not active on the network '
        'yet.',
      ),
      findsOneWidget,
    );
    expect(find.text('Approve this phone'), findsNothing);
    expect(find.text('Remove approved phone'), findsNothing);
  });

  testWidgets('flag reported false -> same plain text', (t) async {
    await _pump(t, _Svc(), _ledger(active: false), phoneKey: _mine);
    expect(find.text('Approve this phone'), findsNothing);
    expect(find.textContaining('not active on the network yet'), findsWidgets);
  });

  testWidgets('active, none approved -> Approve only', (t) async {
    await _pump(
      t,
      _Svc(),
      _ledger(active: true, submitter: null),
      phoneKey: _mine,
    );
    expect(
      find.text(
        'No phone is approved. Only your wallet key can send readings.',
      ),
      findsOneWidget,
    );
    expect(find.text('Approve this phone'), findsOneWidget);
    expect(find.text('Remove approved phone'), findsNothing);
  });

  testWidgets('active, this phone approved -> Remove only', (t) async {
    await _pump(
      t,
      _Svc(),
      _ledger(active: true, submitter: {'pubkey': _mine, 'class': 'device'}),
      phoneKey: _mine,
    );
    expect(
      find.text('This phone is approved to send readings.'),
      findsOneWidget,
    );
    expect(find.text('Approve this phone'), findsNothing);
    expect(find.text('Remove approved phone'), findsOneWidget);
  });

  testWidgets('active, another device approved -> both', (t) async {
    await _pump(
      t,
      _Svc(),
      _ledger(active: true, submitter: {'pubkey': _other, 'class': 'device'}),
      phoneKey: _mine,
    );
    expect(
      find.text('Another device is approved (key ending d5d5d5d5).'),
      findsOneWidget,
    );
    expect(find.text('Approve this phone'), findsOneWidget);
    expect(find.text('Remove approved phone'), findsOneWidget);
  });

  testWidgets('no collect key yet -> says so, no Approve', (t) async {
    await _pump(t, _Svc(), _ledger(active: true, submitter: null));
    expect(
      find.text('This phone has no collect key yet. Turn on Collect first.'),
      findsOneWidget,
    );
    expect(find.text('Approve this phone'), findsNothing);
  });

  testWidgets('frozen -> no change buttons', (t) async {
    await _pump(
      t,
      _Svc(),
      _ledger(active: true, submitter: null, frozen: {'since_height': 900}),
      phoneKey: _mine,
    );
    expect(
      find.text('Unfreeze the station to change the approved phone.'),
      findsOneWidget,
    );
    expect(find.text('Approve this phone'), findsNothing);
  });

  testWidgets('approve: confirm, submit, pending until the ledger shows it', (
    t,
  ) async {
    final svc = _Svc();
    await _pump(
      t,
      svc,
      _ledger(active: true, submitter: null),
      phoneKey: _mine,
    );
    await t.tap(find.text('Approve this phone'));
    await t.pumpAndSettle();
    expect(find.text('Approve this phone to send readings?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Approve this phone'));
    await t.pumpAndSettle();
    expect(svc.calls, [true]);
    expect(find.text('Pending confirmation'), findsOneWidget);
    svc.status = TransferStatus.confirmed;
    await t.tap(find.text('Check again'));
    await t.pumpAndSettle();
    expect(
      find.text('This phone is approved to send readings for your station.'),
      findsOneWidget,
    );
  });

  testWidgets('cancel in the dialog submits nothing', (t) async {
    final svc = _Svc();
    await _pump(
      t,
      svc,
      _ledger(active: true, submitter: {'pubkey': _other, 'class': 'device'}),
      phoneKey: _mine,
    );
    await t.tap(find.text('Remove approved phone'));
    await t.pumpAndSettle();
    expect(find.text('Remove the approved phone?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(svc.calls, isEmpty);
  });

  final fonts = Platform.environment['SCREENSHOT_FONT_DIR'] != null;
  final shots = <String, Map<String, dynamic>>{
    'inactive': ledgerJson(),
    'active-none': _ledger(active: true, submitter: null),
  };
  for (final shot in shots.entries) {
    for (final (width, size) in screenshotSizes) {
      testWidgets('screenshot ${shot.key} $width', skip: !fonts, (t) async {
        await loadScreenshotFonts();
        await _pump(
          t,
          _Svc(),
          shot.value,
          phoneKey: _mine,
          size: Size(size.width, 900),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../../docs/screens/submitter-key/${shot.key}-$width.png',
          ),
        );
      });
    }
  }
}
