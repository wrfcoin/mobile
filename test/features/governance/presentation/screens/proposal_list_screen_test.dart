import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_list_screen.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/widgets/settings_gear_button.dart';

void main() {
  testWidgets('empty list says submitting is unavailable; no treasury shown', (
    tester,
  ) async {
    final calls = <String>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls.add(options.path);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'proposals': <Object>[]},
              ),
            );
          },
        ),
      );
    addTearDown(() => dio.close(force: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          governanceRepositoryProvider.overrideWithValue(
            GovernanceRepository(dio),
          ),
        ],
        child: const MaterialApp(home: ProposalListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        "No proposals yet. Submitting proposals isn't available on testnet yet.",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Treasury'), findsNothing);
    expect(find.textContaining('Balance'), findsNothing);
    expect(find.byType(SettingsGearButton), findsOneWidget);
    expect(calls, [ApiConstants.proposals]);
  });
}
