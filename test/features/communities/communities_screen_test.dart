import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/communities/data/fake/fake_communities_service.dart';
import 'package:wrfcoin_mobile/features/communities/presentation/screens/communities_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import 'communities_test_helpers.dart';

Widget _buildScreen({FakeCommunitiesService? service}) {
  final keyStorage = InMemoryKeyValueStorage();
  keyStorage.write(key: 'wrf_address', value: 'wrf1testhostAAAA');

  return ProviderScope(
    overrides: [
      communitiesServiceProvider.overrideWithValue(
        service ?? FakeCommunitiesService(),
      ),
      keyManagerProvider.overrideWithValue(
        KeyManager(
          storage: keyStorage,
          biometric: BiometricService(client: FakeLocalAuthClient()),
        ),
      ),
    ],
    child: const MaterialApp(home: CommunitiesScreen()),
  );
}

void main() {
  testWidgets('shows loading indicator while initializing', (tester) async {
    await tester.pumpWidget(_buildScreen());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders cluster names after loading', (tester) async {
    await tester.pumpWidget(_buildScreen());
    // pump+100ms instead of pumpAndSettle — avoids any timer-based issues.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Fog Belt Monitors'), findsOneWidget);
    expect(find.text('Delta Weather Watch'), findsOneWidget);
  });

  testWidgets('shows "Local Communities" app bar title', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Local Communities'), findsOneWidget);
  });

  testWidgets('tapping a cluster card selects it', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Delta Weather Watch'));
    await tester.pump(const Duration(milliseconds: 100));

    // After selecting, the detail panel shows (tabs visible).
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Challenges'), findsOneWidget);
  });

  testWidgets('location sharing toggle is off by default', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump(const Duration(milliseconds: 100));

    final toggle = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(toggle.value, isFalse);
  });

  testWidgets('toggling location sharing updates state', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump(const Duration(milliseconds: 100));

    final toggle = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(toggle.value, isTrue);
  });
}
