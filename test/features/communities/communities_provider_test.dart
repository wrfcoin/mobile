import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/communities/data/communities_service.dart';
import 'package:wrfcoin_mobile/features/communities/data/fake/fake_communities_service.dart';
import 'package:wrfcoin_mobile/features/communities/presentation/providers/communities_provider.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import 'communities_test_helpers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _makeContainer({CommunitiesService? service}) {
  final keyStorage = InMemoryKeyValueStorage();
  keyStorage.write(key: 'wrf_address', value: 'wrf1test0000abcdef');

  final container = ProviderContainer(overrides: [
    communitiesServiceProvider.overrideWithValue(
      service ?? FakeCommunitiesService(),
    ),
    keyManagerProvider.overrideWithValue(
      KeyManager(
        storage: keyStorage,
        biometric: BiometricService(client: FakeLocalAuthClient()),
      ),
    ),
  ]);

  addTearDown(container.dispose);
  return container;
}

/// Wait until the provider's loading flag becomes false (or timeout after 5 s).
/// Uses a listener so we don't race against async initialization.
Future<void> _waitForLoaded(ProviderContainer container) async {
  // Read once to trigger initialization if not already started.
  if (!container.read(communitiesProvider).loading) return;

  final loaded = Completer<void>();
  final sub = container.listen<CommunitiesState>(
    communitiesProvider,
    (_, state) {
      if (!state.loading && !loaded.isCompleted) loaded.complete();
    },
    fireImmediately: false,
  );
  try {
    await loaded.future.timeout(const Duration(seconds: 5));
  } finally {
    sub.close();
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  test('initial state has loading=true', () {
    final container = _makeContainer();
    final state = container.read(communitiesProvider);
    expect(state.loading, isTrue);
  });

  test('after initialization clusters are loaded', () async {
    final container = _makeContainer();
    await _waitForLoaded(container);
    final state = container.read(communitiesProvider);
    expect(state.loading, isFalse);
    expect(state.clusters, isNotEmpty);
  });

  test('selectedCluster defaults to first cluster', () async {
    final container = _makeContainer();
    await _waitForLoaded(container);
    final state = container.read(communitiesProvider);
    expect(state.selectedCluster, isNotNull);
    expect(state.selectedCluster, same(state.clusters.first));
  });

  test('selectCluster updates selectedCluster', () async {
    final container = _makeContainer();
    await _waitForLoaded(container);

    final clusters = container.read(communitiesProvider).clusters;
    final target = clusters.last;

    container.read(communitiesProvider.notifier).selectCluster(target.id);
    final state = container.read(communitiesProvider);
    expect(state.selectedCluster?.id, target.id);
  });

  test('joinByInviteCode adds user to joined clusters', () async {
    final container = _makeContainer();
    await _waitForLoaded(container);

    expect(container.read(communitiesProvider).joinedClusters, isEmpty);

    await container
        .read(communitiesProvider.notifier)
        .joinByInviteCode('FOGBLT');
    await _waitForLoaded(container);

    final state = container.read(communitiesProvider);
    expect(state.joinedClusters, isNotEmpty);
    expect(state.joinedClusters.first.inviteCode, 'FOGBLT');
  });

  test('joinByInviteCode with bad code sets error on state', () async {
    final container = _makeContainer();
    await _waitForLoaded(container);

    await container
        .read(communitiesProvider.notifier)
        .joinByInviteCode('BADCODE');
    await _waitForLoaded(container);

    final state = container.read(communitiesProvider);
    expect(state.joining, isFalse);
    expect(state.error, isA<ValidationFailure>());
  });

  test('postMessage appends message to selected cluster', () async {
    final container = _makeContainer();
    await _waitForLoaded(container);

    final before =
        container.read(communitiesProvider).selectedCluster!.messages.length;

    await container
        .read(communitiesProvider.notifier)
        .postMessage('Fog is heavy today');
    await _waitForLoaded(container);

    final after =
        container.read(communitiesProvider).selectedCluster!.messages.length;
    expect(after, before + 1);
    expect(
      container
          .read(communitiesProvider)
          .selectedCluster!
          .messages
          .last
          .content,
      'Fog is heavy today',
    );
  });

  test('leaveCluster removes cluster from joinedClusters', () async {
    final container = _makeContainer();
    await _waitForLoaded(container);

    await container
        .read(communitiesProvider.notifier)
        .joinByInviteCode('FOGBLT');
    await _waitForLoaded(container);
    expect(container.read(communitiesProvider).joinedClusters, isNotEmpty);

    final clusterId =
        container.read(communitiesProvider).joinedClusters.first.id;
    await container
        .read(communitiesProvider.notifier)
        .leaveCluster(clusterId);
    await _waitForLoaded(container);

    expect(container.read(communitiesProvider).joinedClusters, isEmpty);
  });

  test('setLocationSharing updates locationSharingEnabled', () async {
    final container = _makeContainer();
    await _waitForLoaded(container);

    expect(
      container.read(communitiesProvider).locationSharingEnabled,
      isFalse,
    );

    container
        .read(communitiesProvider.notifier)
        .setLocationSharing(enabled: true, geohash: '9q8yy');
    await _waitForLoaded(container);

    final state = container.read(communitiesProvider);
    expect(state.locationSharingEnabled, isTrue);
    expect(state.userGeohash, '9q8yy');
  });

  test('setLocationSharing(false) clears geohash', () async {
    final container = _makeContainer();
    await _waitForLoaded(container);

    container.read(communitiesProvider.notifier).setLocationSharing(
      enabled: true,
      geohash: '9q8yy',
    );
    await _waitForLoaded(container);

    container.read(communitiesProvider.notifier).setLocationSharing(
      enabled: false,
    );
    await _waitForLoaded(container);

    final state = container.read(communitiesProvider);
    expect(state.locationSharingEnabled, isFalse);
    expect(state.userGeohash, isNull);
  });
}
