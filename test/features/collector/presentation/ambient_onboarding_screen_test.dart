import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/ambient_onboarding_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';

import '../../../test_helpers/ambient_transport.dart';

class _Flags extends FeatureFlagsNotifier {
  _Flags(this.enabled);
  final bool enabled;
  @override
  FeatureFlags build() => FeatureFlags(enablePwsAutoDiscovery: enabled);
  void withdraw() => state = state.copyWith(enablePwsAutoDiscovery: false);
}

class _Wallet extends WalletNotifier {
  _Wallet(this.address);
  final String? address;
  @override
  Future<WalletModel?> build() async =>
      address == null ? null : WalletModel(address: address!, balance: '0');
  void switchOwner() => state = const AsyncData(
    WalletModel(address: 'wrf1syntheticother', balance: '0'),
  );
}

void main() {
  late AmbientTransport transport;
  late _Flags flags;
  late _Wallet wallet;
  Future<void> mount(
    WidgetTester tester, {
    bool enabled = true,
    String? owner = 'wrf1syntheticowner',
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    transport = AmbientTransport();
    flags = _Flags(enabled);
    wallet = _Wallet(owner);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          featureFlagsProvider.overrideWith(() => flags),
          walletProvider.overrideWith(() => wallet),
          apiClientProvider.overrideWithValue(transport.client()),
        ],
        child: const MaterialApp(home: AmbientOnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> keys(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('ambient-api-key')),
      ambientKeys[0],
    );
    await tester.enterText(
      find.byKey(const ValueKey('ambient-app-key')),
      ambientKeys[1],
    );
    await tester.tap(find.text('Find account stations'));
    await tester.pump();
  }

  String keyText(WidgetTester tester, String id) =>
      tester.widget<TextField>(find.byKey(ValueKey(id))).controller!.text;

  testWidgets('flag and wallet gates issue no discovery requests', (
    tester,
  ) async {
    await mount(tester, enabled: false);
    expect(find.text('Ambient onboarding is disabled.'), findsOneWidget);
    expect(transport.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, owner: null);
    expect(
      find.text('Sign in from Wallet before connecting a station.'),
      findsOneWidget,
    );
    expect(transport.requests, isEmpty);
  });
  testWidgets(
    'explicit account selection registers coarse data, clears keys and makes no reward claim',
    (tester) async {
      await mount(tester);
      expect(transport.requests, isEmpty);
      for (final id in ['ambient-api-key', 'ambient-app-key']) {
        final field = tester.widget<TextField>(find.byKey(ValueKey(id)));
        expect(field.obscureText, isTrue);
        expect(field.enableSuggestions, isFalse);
        expect(field.enableIMEPersonalizedLearning, isFalse);
      }
      await keys(tester);
      await tester.pumpAndSettle();
      expect(transport.requests, hasLength(1));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.contains(ambientKeys[0]) ?? false),
        ),
        findsNothing,
      );
      expect(find.text('Select your account station'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Register selected station'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Select your account station'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ambient station • ee02').last);
      await tester.pumpAndSettle();
      for (final entry in {
        'ambient-station-name': 'Synthetic station',
        'ambient-latitude': '12.3456',
        'ambient-longitude': '-45.6789',
      }.entries) {
        await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
      }
      transport.payload = ambientReceipt;
      await tester.tap(find.text('Register selected station'));
      await tester.pumpAndSettle();
      expect(transport.requests.last.data['mac'], 'aabbccddee02');
      expect(transport.requests.last.data['latitude'], 12.3);
      expect(transport.requests, hasLength(2));
      expect(
        find.text(
          'Registration received. Chain activation and rewards are not confirmed.',
        ),
        findsOneWidget,
      );
      expect(keyText(tester, 'ambient-api-key'), isEmpty);
      expect(keyText(tester, 'ambient-app-key'), isEmpty);
      expect(find.text('Select your account station'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'credential edit and unsuccessful reverification discard the previous account',
    (tester) async {
      await mount(tester);
      await keys(tester);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ambient-app-key')),
        'changed-synthetic-key',
      );
      await tester.pump();
      expect(find.text('Select your account station'), findsNothing);
      await keys(tester);
      await tester.pumpAndSettle();
      transport.payload = {'valid': false, 'devices': []};
      await tester.tap(find.text('Find account stations'));
      await tester.pumpAndSettle();
      expect(find.text('Select your account station'), findsNothing);
      expect(find.byKey(const ValueKey('ambient-error')), findsOneWidget);
    },
  );
  testWidgets(
    'wallet change during registration cancels the request and suppresses a late receipt',
    (tester) async {
      await mount(tester);
      await keys(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select your account station'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ambient station • ee01').last);
      await tester.pumpAndSettle();
      for (final entry in {
        'ambient-station-name': 'Synthetic station',
        'ambient-latitude': '12.3',
        'ambient-longitude': '-45.7',
      }.entries) {
        await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
      }
      final pending = Completer<Object?>();
      transport.respond = (_) => pending.future;
      await tester.tap(find.text('Register selected station'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(transport.requests, hasLength(2));
      wallet.switchOwner();
      await tester.pump();
      pending.complete(ambientReceipt);
      await tester.pumpAndSettle();
      expect(transport.cancelled, ['/weather/stations']);
      expect(find.byKey(const ValueKey('ambient-received')), findsNothing);
      expect(keyText(tester, 'ambient-api-key'), isEmpty);
      expect(keyText(tester, 'ambient-app-key'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final change in ['pause', 'wallet', 'flag', 'unmount']) {
    testWidgets(
      '$change cancels verification and ignores a late account result',
      (tester) async {
        await mount(tester);
        final pending = Completer<Object?>();
        transport.respond = (_) => pending.future;
        await keys(tester);
        await tester.pump(const Duration(milliseconds: 20));
        expect(transport.requests, hasLength(1));
        switch (change) {
          case 'pause':
            for (final state in [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
              tester.binding.handleAppLifecycleStateChanged(state);
            }
          case 'wallet':
            wallet.switchOwner();
          case 'flag':
            flags.withdraw();
          case 'unmount':
            await tester.pumpWidget(const SizedBox());
        }
        await tester.pump();
        pending.complete(ambientDevices);
        await tester.pumpAndSettle();
        expect(transport.cancelled, ['/weather/stations/verify-key']);
        expect(find.text('Select your account station'), findsNothing);
        expect(find.byKey(const ValueKey('ambient-received')), findsNothing);
        if (change == 'pause') {
          for (final state in [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await tester.pumpAndSettle();
        }
        if (change == 'pause' || change == 'wallet') {
          expect(keyText(tester, 'ambient-api-key'), isEmpty);
          expect(keyText(tester, 'ambient-app-key'), isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
