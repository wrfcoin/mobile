import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/advisory_propose_screen.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_detail_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/advisory_action_signing.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/transfer_signing_domain.dart';

import '../../test_helpers/fakes.dart';
import 'fixtures/advisory_api.dart';

// In-app advisory voting screens. Renders with SCREENSHOT_FONTS set to
// Flutter's bin/cache/artifacts/material_fonts:
// flutter test --update-goldens test/features/governance/advisory_vote_screenshots_test.dart
// The wallet is the synthetic core4 vector key (seed 0x42 x 32); the
// proposal is the live "Welcome" proposal's shape.
void main() {
  final fonts = Platform.environment['SCREENSHOT_FONTS'];

  Future<void> load(String family, String file) async {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(
          ByteData.sublistView(File('$fonts/$file').readAsBytesSync()),
        ),
      );
    await loader.load();
  }

  const id = 'adv-a75dae543f5f9e16';
  const widths = {'phone-390': Size(390, 844), 'desktop-1280': Size(1280, 800)};
  for (final MapEntry(key: name, value: size) in widths.entries) {
    testWidgets('$name vote screenshots', (tester) async {
      await load('Roboto', 'Roboto-Regular.ttf');
      await load('MaterialIcons', 'MaterialIcons-Regular.otf');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<FakeAdvisoryApi> show(
        Map<String, dynamic> eligibility, {
        Widget home = const ProposalDetailScreen(proposalId: id),
        String balance = '10900000000',
        bool resumeAfterUnlock = true,
      }) async {
        LoginAttemptGuard.resetIsolateStateForTest();
        final auth = FakeLocalAuthClient();
        final keys = KeyManager(
          biometric: BiometricService(client: auth),
          storage: InMemoryKeyValueStorage(),
        );
        await keys.storeKeys(
          mnemonic: 'synthetic',
          privateKey: '4242424242424242424242424242424242424242424242424242424242424242',
          address: '0xa307fb31c7585b6ccb5dc3ddc844e22b14b7aa0d',
          keyScheme: KeyManager.canonicalKeyScheme,
        );
        final api = FakeAdvisoryApi(
          [welcomeProposalJson()],
          eligibility: eligibility,
          balance: balance,
          nonce: 0,
        );
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              appPreferencesStoreProvider.overrideWithValue(
                TestAppPreferencesStore(),
              ),
              governanceRepositoryProvider.overrideWithValue(
                GovernanceRepository(
                  api.dio(),
                  advisorySigner: AdvisoryActionSigner(
                    keyManager: keys,
                    domain: const TransferSigningDomain(
                      chainId: '888',
                      networkId: 'testnet',
                    ),
                    isForeground: () =>
                        resumeAfterUnlock ||
                        auth.authenticateBiometricOnlyCalls.isEmpty,
                    resumeTimeout: const Duration(milliseconds: 300),
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme.copyWith(
                textTheme: AppTheme.darkTheme.textTheme.apply(
                  fontFamily: 'Roboto',
                ),
              ),
              home: DefaultTextStyle.merge(
                style: const TextStyle(fontFamily: 'Roboto'),
                child: home,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final panel = find.byKey(const Key('advisory-vote-panel'));
        if (panel.evaluate().isNotEmpty) {
          await tester.ensureVisible(panel);
          await tester.pumpAndSettle();
        }
        return api;
      }

      Future<void> shot(String scene) => expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screens/governance/$scene-$name.png'),
      );

      // 1. Eligible: the vote buttons.
      final api = await show(eligibleJson());
      await shot('vote-eligible');

      // 2. The confirm sheet: exactly what is signed.
      await tester.tap(find.byKey(const Key('advisory-vote-for')));
      await tester.pumpAndSettle();
      await shot('vote-sheet');

      // 3. Sent: pending until it is in a block.
      await tester.tap(find.byKey(const Key('sheet-confirm')));
      await tester.pumpAndSettle();
      await shot('vote-sent');

      // 4. The result about a block later: the tally moved, "already voted".
      api.proposals[0] = {...welcomeProposalJson(), 'yes_votes': 2};
      api.eligibility = votedJson('for');
      await tester.pump(const Duration(seconds: 91));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('advisory-vote-panel')));
      await tester.pumpAndSettle();
      await shot('vote-result');

      // 5. Not eligible: said plainly.
      await show(notEligibleJson());
      await shot('vote-not-eligible');

      // 6. The relay's answer was lost after sending: not "failed".
      final lost = await show(eligibleJson());
      lost.actionTransportError = DioExceptionType.receiveTimeout;
      await tester.tap(find.byKey(const Key('advisory-vote-for')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet-confirm')));
      await tester.pumpAndSettle();
      await shot('vote-unknown');
      // Let the panel's re-read timer run out before the next scene.
      await tester.pump(const Duration(seconds: 91));
      await tester.pumpAndSettle();

      // Propose: the form with live byte counters, the sheet, sent.
      await show(eligibleJson(), home: const AdvisoryProposeScreen());
      await tester.enterText(
        find.byKey(const Key('advisory-title')),
        'Report every 10 minutes?',
      );
      await tester.enterText(
        find.byKey(const Key('advisory-summary')),
        'Synthetic text: should stations report every 10 minutes instead '
        'of every 5? Advisory only.',
      );
      await tester.pumpAndSettle();
      await shot('propose-form');
      await tester.tap(find.byKey(const Key('advisory-propose-review')));
      await tester.pumpAndSettle();
      await shot('propose-sheet');
      await tester.tap(find.byKey(const Key('sheet-confirm')));
      await tester.pumpAndSettle();
      await shot('propose-sent');

      // Propose refused: under 1 WRF.
      await show(
        eligibleJson(),
        home: const AdvisoryProposeScreen(),
        balance: '50000000',
      );
      await tester.enterText(find.byKey(const Key('advisory-title')), 'T');
      await tester.enterText(find.byKey(const Key('advisory-summary')), 'S');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('advisory-propose-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet-confirm')));
      await tester.pumpAndSettle();
      await shot('propose-refused');

      // Propose: the app was not back on screen after the unlock.
      await show(
        eligibleJson(),
        home: const AdvisoryProposeScreen(),
        resumeAfterUnlock: false,
      );
      await tester.enterText(find.byKey(const Key('advisory-title')), 'T');
      await tester.enterText(find.byKey(const Key('advisory-summary')), 'S');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('advisory-propose-review')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('sheet-confirm')));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();
      await shot('propose-not-on-screen');
    }, skip: fonts == null);
  }
}
