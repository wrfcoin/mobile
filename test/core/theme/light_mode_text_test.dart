import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/widgets/proposal_card.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/auth_handoff_banner.dart';

/// The near-white [AppColors.textPrimary] only reads on a surface that stays
/// dark in both themes. These are the places that use it on purpose.
const _alwaysDark = {
  'lib/core/theme/app_theme.dart',
  // A gradient card, dark in both themes.
  'lib/features/collector/presentation/widgets/share_card.dart',
  // The rank circle is AppColors.surfaceLight, dark in both themes.
  'lib/features/gamification/presentation/screens/leaderboard_screen.dart',
  // The tooltip is AppColors.surface, dark in both themes.
  'lib/features/weather/presentation/widgets/wrf_forecast_chart.dart',
};

Color _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

void main() {
  test('near-white text is used only on surfaces that stay dark', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('AppColors.textPrimary'))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((path) => !_alwaysDark.contains(path))
        .toList();
    expect(offenders, isEmpty);
  });

  testWidgets('a proposal title is dark on the light theme', (tester) async {
    const proposal = ProposalModel(
      id: 'p1',
      title: 'Sample proposal',
      description: 'Text',
      status: 'active',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: ProposalCard(proposal: proposal)),
      ),
    );
    expect(_colorOf(tester, 'Sample proposal'), AppColors.lightTextPrimary);
  });

  testWidgets('a handoff message reads on its pale amber card', (tester) async {
    final handoff = AuthHandoffController()
      ..requireWalletConnect(
        reason: AuthHandoffReason.unsupportedWallet,
        message: 'Handoff message',
      );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              Scaffold(body: AuthHandoffBanner(handoff: handoff)),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_colorOf(tester, 'Handoff message'), Colors.amber.shade900);
  });
}
