import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registrar_service.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/station_registrar_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/station_registrar_card.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../../../test_helpers/fake_station_backend.dart';

class _FakeService extends StationRegistrarService {
  _FakeService() : super(apiClient: ApiClient(dio: Dio()));
  int requests = 0;
  RegistrarRequestException? refuse;

  @override
  Future<RegistrarStatus> request(StationSigningSession session) async {
    requests++;
    final r = refuse;
    if (r != null) throw r;
    return RegistrarStatus(
      RegistrarState.held,
      releaseAt: DateTime.utc(2026, 11, 22, 20),
    );
  }
}

/// Real key reads and signing run outside the fake clock: let them finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
  fail('request did not finish');
}

void main() {
  late _FakeService service;
  late bool biometricGranted;
  late RegistrarStatus? current;
  late int opens;

  setUp(() {
    service = _FakeService();
    biometricGranted = true;
    current = RegistrarStatus.notRequested;
    opens = 0;
  });

  Future<void> pump(WidgetTester tester) async {
    // Real key read and signing, done once outside the fake clock.
    final session = biometricGranted
        ? await tester.runAsync(() => SyntheticSigner().open())
        : null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stationRegistrarServiceProvider.overrideWithValue(service),
          stationRegistrarSessionOpenerProvider.overrideWithValue(() async {
            opens++;
            return session;
          }),
          stationRegistrarStatusProvider.overrideWith(
            (ref, id) async => current,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: StationRegistrarCard(ownerAddress: syntheticAddress),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders nothing while requests are not open', (tester) async {
    current = null;
    await pump(tester);
    expect(find.byKey(const Key('station-registrar-card')), findsNothing);
    expect(opens, 0);
  });

  testWidgets('offers one request; the wallet signs only on tap', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('station-registrar-card')), findsOneWidget);
    expect(find.text(RegistrarStatus.notRequested.message), findsOneWidget);
    expect(opens, 0);
    current = RegistrarStatus(
      RegistrarState.held,
      releaseAt: DateTime.utc(2026, 11, 22, 20),
    );
    await tester.tap(find.byKey(const Key('station-registrar-request')));
    await settle(tester);
    await tester.pump();
    await tester.pump();
    expect(opens, 1);
    expect(service.requests, 1);
    expect(find.byKey(const Key('station-registrar-request')), findsNothing);
    expect(find.byKey(const Key('station-registrar-release')), findsOneWidget);
  });

  testWidgets('a refused biometric prompt sends nothing', (tester) async {
    biometricGranted = false;
    await pump(tester);
    await tester.tap(find.byKey(const Key('station-registrar-request')));
    await settle(tester);
    await tester.pump();
    expect(service.requests, 0);
    expect(find.text(RegistrarRefusal.cancelled.userMessage), findsOneWidget);
    expect(find.byKey(const Key('station-registrar-request')), findsOneWidget);
  });

  testWidgets('a refusal shows fixed text and keeps the button', (
    tester,
  ) async {
    service.refuse = const RegistrarRequestException(RegistrarRefusal.limit);
    await pump(tester);
    await tester.tap(find.byKey(const Key('station-registrar-request')));
    await settle(tester);
    await tester.pump();
    expect(service.requests, 1);
    expect(find.text(RegistrarRefusal.limit.userMessage), findsOneWidget);
  });

  testWidgets('each later state shows its own text and no button', (
    tester,
  ) async {
    for (final state in [
      RegistrarState.submitted,
      RegistrarState.registered,
      RegistrarState.refused,
      RegistrarState.needsReview,
    ]) {
      current = RegistrarStatus(state);
      await pump(tester);
      expect(
        find.text(RegistrarStatus(state).message),
        findsOneWidget,
        reason: '$state',
      );
      expect(find.byKey(const Key('station-registrar-request')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
