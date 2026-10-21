import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/vote_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';

import '../../../../test_helpers/fakes.dart';

void main() {
  const proposal = ProposalModel(
    id: 'p1',
    title: 'Increase Treasury Spending Limit',
    description: 'Raise max single-tx treasury spend to 100k WRF.',
    proposalType: 'treasury_spending',
    status: 'active',
    votesFor: 10,
    votesAgainst: 5,
    votesAbstain: 2,
  );

  Widget buildWidget({FakeLocalAuthClient? authClient}) {
    return ProviderScope(
      overrides: [
        governanceRepositoryProvider.overrideWithValue(
          FakeGovernanceRepository(),
        ),
        biometricServiceProvider.overrideWithValue(
          BiometricService(client: authClient ?? FakeLocalAuthClient()),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => VoteScreen(proposal: proposal),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('renders proposal title and two vote options', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Increase Treasury Spending Limit'), findsOneWidget);
    expect(find.text('Vote For'), findsOneWidget);
    expect(find.text('Vote Against'), findsOneWidget);
    expect(find.text('Abstain'), findsNothing);
  });

  testWidgets('only chain-supported choices are offered', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Abstain'), findsNothing);
  });

  testWidgets('confirmation precedes the one wallet key authentication', (
    tester,
  ) async {
    final auth = FakeLocalAuthClient();
    await tester.pumpWidget(buildWidget(authClient: auth));
    await tester.tap(find.text('Vote For'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Vote'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Confirm Vote'), findsOneWidget);
    expect(auth.authenticateBiometricOnlyCalls, isEmpty);
  });

  testWidgets('shows biometric hint text', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Biometric authentication required before voting'),
      findsOneWidget,
    );
  });

  testWidgets('submit button is disabled before selecting a vote', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump(const Duration(milliseconds: 100));

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submit Vote'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('submit button is enabled after selecting FOR', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Vote For'));
    await tester.pump(const Duration(milliseconds: 100));

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submit Vote'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('submit button is enabled after selecting AGAINST', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Vote Against'));
    await tester.pump(const Duration(milliseconds: 100));

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submit Vote'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('shows confirm dialog before wallet authentication', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildWidget(authClient: FakeLocalAuthClient(authenticateResult: true)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Vote For'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Vote'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Confirm Vote'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cast Vote'), findsOneWidget);
  });

  testWidgets('submits vote and dismisses after confirm dialog confirmed', (
    tester,
  ) async {
    bool popped = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          governanceRepositoryProvider.overrideWithValue(
            FakeGovernanceRepository(),
          ),
          biometricServiceProvider.overrideWithValue(
            BiometricService(
              client: FakeLocalAuthClient(authenticateResult: true),
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) =>
                    const Scaffold(body: Text('Parent')),
                routes: [
                  GoRoute(
                    path: 'vote',
                    builder: (context, state) => VoteScreen(proposal: proposal),
                    onExit: (context, state) async {
                      popped = true;
                      return true;
                    },
                  ),
                ],
              ),
            ],
            initialLocation: '/vote',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Vote For'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Vote'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Confirm Vote'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cast Vote'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(popped, isTrue);
  });
}
