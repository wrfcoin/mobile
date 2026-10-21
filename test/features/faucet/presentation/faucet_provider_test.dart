import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/faucet/data/models/faucet_models.dart';
import 'package:wrfcoin_mobile/features/faucet/data/repositories/faucet_repository.dart';
import 'package:wrfcoin_mobile/features/faucet/presentation/providers/faucet_provider.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../../test_helpers/fakes.dart';

/// In-memory fake of [FaucetRepository] with scriptable outcomes.
class _FakeFaucetRepository implements FaucetRepository {
  Either<Failure, FaucetChallenge> challengeResult = Right(
    const FaucetChallenge(challengeId: 'c1', question: 'What is 1 + 1?'),
  );
  Either<Failure, FaucetClaimResult> claimResult = Right(
    const FaucetClaimResult(txHash: '0xabc', amount: '100', balance: '100'),
  );

  int? lastAnswer;

  @override
  Future<Either<Failure, FaucetChallenge>> requestChallenge() async =>
      challengeResult;

  @override
  Future<Either<Failure, FaucetClaimResult>> claim({
    required String walletAddress,
    required String challengeId,
    required int answer,
  }) async {
    lastAnswer = answer;
    return claimResult;
  }
}

ProviderContainer _container(
  _FakeFaucetRepository repo, {
  String? address = '0x1111111111111111111111111111111111111111',
}) {
  final storage = InMemoryKeyValueStorage();
  if (address != null) {
    storage.write(key: 'wrf_address', value: address);
  }

  final container = ProviderContainer(overrides: [
    faucetRepositoryProvider.overrideWithValue(repo),
    keyManagerProvider.overrideWithValue(
      KeyManager(
        storage: storage,
        biometric: BiometricService(client: FakeLocalAuthClient()),
      ),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Waits until [test] holds for the faucet state, polling via a listener.
Future<void> _waitFor(
  ProviderContainer container,
  bool Function(FaucetState) test,
) async {
  if (test(container.read(faucetProvider))) return;
  final done = Completer<void>();
  final sub = container.listen<FaucetState>(faucetProvider, (_, state) {
    if (test(state) && !done.isCompleted) done.complete();
  });
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    sub.close();
  }
}

void main() {
  test('resolves wallet address from key manager on build', () async {
    final container = _container(_FakeFaucetRepository());
    await _waitFor(container, (s) => s.hasWallet);
    expect(
      container.read(faucetProvider).walletAddress,
      '0x1111111111111111111111111111111111111111',
    );
  });

  test('requestChallenge populates the challenge', () async {
    final container = _container(_FakeFaucetRepository());
    await container.read(faucetProvider.notifier).requestChallenge();

    final state = container.read(faucetProvider);
    expect(state.hasChallenge, isTrue);
    expect(state.challenge!.question, 'What is 1 + 1?');
    expect(state.loadingChallenge, isFalse);
  });

  test('successful claim emits result and clears the challenge', () async {
    final repo = _FakeFaucetRepository();
    final container = _container(repo);
    await _waitFor(container, (s) => s.hasWallet);

    await container.read(faucetProvider.notifier).requestChallenge();
    await container.read(faucetProvider.notifier).claim('2');

    final state = container.read(faucetProvider);
    expect(repo.lastAnswer, 2);
    expect(state.result, isNotNull);
    expect(state.result!.txHash, '0xabc');
    expect(state.hasChallenge, isFalse);
    expect(state.error, isNull);
  });

  test('backend failure surfaces error and drops the challenge', () async {
    final repo = _FakeFaucetRepository()
      ..claimResult = Left(
        const ServerFailure(
          'This address has already claimed tokens within the last 24 hours',
          statusCode: 429,
        ),
      );
    final container = _container(repo);
    await _waitFor(container, (s) => s.hasWallet);

    await container.read(faucetProvider.notifier).requestChallenge();
    await container.read(faucetProvider.notifier).claim('2');

    final state = container.read(faucetProvider);
    expect(state.result, isNull);
    expect(state.error, isA<ServerFailure>());
    expect(state.error!.statusCode, 429);
    expect(state.hasChallenge, isFalse);
  });

  test('non-numeric answer is rejected without calling the backend', () async {
    final repo = _FakeFaucetRepository();
    final container = _container(repo);
    await _waitFor(container, (s) => s.hasWallet);

    await container.read(faucetProvider.notifier).requestChallenge();
    await container.read(faucetProvider.notifier).claim('not-a-number');

    final state = container.read(faucetProvider);
    expect(state.error, isA<ValidationFailure>());
    expect(repo.lastAnswer, isNull);
  });

  test('claim without a wallet yields an auth failure', () async {
    final container = _container(_FakeFaucetRepository(), address: null);
    // build() kicks off async address load; it resolves to null.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container.read(faucetProvider.notifier).claim('2');

    expect(container.read(faucetProvider).error, isA<AuthFailure>());
  });
}
