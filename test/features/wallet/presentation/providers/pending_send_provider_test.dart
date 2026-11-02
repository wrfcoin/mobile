import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/pending_send.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/pending_send_provider.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../../../test_helpers/fakes.dart';

const _wallet = '0x1234567890abcdef1234567890abcdef12345678';
const _to = '0x2222222222222222222222222222222222222222';
final _start = DateTime.utc(2026, 11, 1, 12);
final _hash = List.filled(64, 'a').join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWalletRepository repository;
  late FakeWalletSecureStorage storage;
  late DateTime now;

  Future<ProviderContainer> container({String wallet = _wallet}) async {
    final keys = InMemoryKeyValueStorage();
    await keys.write(key: 'wrf_address', value: wallet);
    final container = ProviderContainer(
      overrides: [
        walletRepositoryProvider.overrideWithValue(repository),
        walletSecureStorageProvider.overrideWithValue(storage),
        keyManagerProvider.overrideWithValue(
          KeyManager(
            biometric: BiometricService(client: FakeLocalAuthClient()),
            storage: keys,
          ),
        ),
        pendingSendClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Starts a provider and lets its load and first check finish.
  Future<PendingSendNotifier> started(ProviderContainer c) async {
    final notifier = c.read(pendingSendProvider.notifier);
    await notifier.ready;
    await notifier.check();
    return notifier;
  }

  /// A send the backend has accepted, signed with nonce 7.
  Future<PendingSendNotifier> submitted(ProviderContainer c) async {
    final notifier = c.read(pendingSendProvider.notifier);
    await notifier.begin(
      from: _wallet,
      to: _to,
      amountBaseUnits: '50000000',
      nonce: '7',
    );
    await notifier.markSubmitted(_hash);
    return notifier;
  }

  PendingSendState stateOf(ProviderContainer c) => c.read(pendingSendProvider);

  setUp(() {
    repository = FakeWalletRepository();
    storage = FakeWalletSecureStorage();
    now = _start;
  });

  test('nothing saved: nothing shown and nothing blocked', () async {
    final c = await container();
    await started(c);
    expect(stateOf(c).send, isNull);
    expect(stateOf(c).blocksSend, isFalse);
  });

  group('the chain decides', () {
    test('an unchanged nonce stays pending and blocks Send', () async {
      final c = await container();
      final notifier = await submitted(c);
      await notifier.check();
      expect(stateOf(c).send!.phase, PendingSendPhase.submitted);
      expect(stateOf(c).blocksSend, isTrue);
      expect(stateOf(c).checkFailed, isFalse);
    });

    test(
      'nonce moved and the send in history: confirmed, with its block',
      () async {
        final c = await container();
        final notifier = await submitted(c);
        repository
          ..accountNonceResult = const Right('8')
          ..includedBlockResult = const Right(4242);
        await notifier.check();
        expect(stateOf(c).send!.phase, PendingSendPhase.included);
        expect(stateOf(c).send!.blockHeight, 4242);
        expect(stateOf(c).blocksSend, isFalse);
      },
    );

    test('in history but the nonce has not moved: not confirmed', () async {
      final c = await container();
      final notifier = await submitted(c);
      repository.includedBlockResult = const Right(4242);
      await notifier.check();
      expect(stateOf(c).send!.phase, PendingSendPhase.submitted);
      expect(stateOf(c).blocksSend, isTrue);
    });

    for (final (name, result) in <(String, Either<Failure, int?>)>[
      ('missing from history', const Right(null)),
      ('history unreadable', const Left(ServerFailure('down'))),
    ]) {
      test('nonce moved, $name: not confirmed, and Send is free', () async {
        final c = await container();
        final notifier = await submitted(c);
        repository
          ..accountNonceResult = const Right('8')
          ..includedBlockResult = result;
        await notifier.check();
        expect(stateOf(c).send!.phase, PendingSendPhase.nonceUsedUnmatched);
        expect(stateOf(c).blocksSend, isFalse);

        // History catches up on a later read.
        repository.includedBlockResult = const Right(4243);
        await notifier.check();
        expect(stateOf(c).send!.phase, PendingSendPhase.included);
      });
    }

    test('with no id from the backend it can never say confirmed', () async {
      final c = await container();
      final notifier = c.read(pendingSendProvider.notifier);
      await notifier.begin(
        from: _wallet,
        to: _to,
        amountBaseUnits: '1',
        nonce: '7',
      );
      await notifier.markSubmitted(null);
      repository
        ..accountNonceResult = const Right('8')
        ..includedBlockResult = const Right(4242);
      await notifier.check();
      expect(stateOf(c).send!.phase, PendingSendPhase.nonceUsedUnmatched);
    });

    test('a nonce behind the signed one stays pending', () async {
      final c = await container();
      final notifier = await submitted(c);
      repository.accountNonceResult = const Right('6');
      await notifier.check();
      expect(stateOf(c).send!.phase, PendingSendPhase.submitted);
    });
  });

  group('it never gets stuck', () {
    test('a failed read says so and still blocks inside the limit', () async {
      final c = await container();
      final notifier = await submitted(c);
      repository.accountNonceResult = const Left(NetworkFailure());
      await notifier.check();
      expect(stateOf(c).checkFailed, isTrue);
      expect(stateOf(c).blocksSend, isTrue);

      repository.accountNonceResult = const Right('7');
      await notifier.check();
      expect(stateOf(c).checkFailed, isFalse);
    });

    test('at the time limit Send is free even if reads keep failing', () async {
      final c = await container();
      final notifier = await submitted(c);
      repository.accountNonceResult = const Left(NetworkFailure());
      now = _start.add(pendingSendTimeLimit - const Duration(seconds: 1));
      await notifier.check();
      expect(stateOf(c).blocksSend, isTrue);

      now = _start.add(pendingSendTimeLimit);
      await notifier.check();
      expect(stateOf(c).overdue, isTrue);
      expect(stateOf(c).blocksSend, isFalse);
      expect(stateOf(c).send!.phase, PendingSendPhase.submitted);
    });

    test('the limit passes the replay window, so no fresh 409', () {
      expect(pendingSendTimeLimit, greaterThan(const Duration(minutes: 10)));
    });

    test('an overdue send can still come in as confirmed', () async {
      final c = await container();
      final notifier = await submitted(c);
      now = _start.add(pendingSendTimeLimit);
      await notifier.check();
      repository
        ..accountNonceResult = const Right('8')
        ..includedBlockResult = const Right(4242);
      await notifier.check();
      expect(stateOf(c).send!.phase, PendingSendPhase.included);
      expect(stateOf(c).overdue, isFalse);
    });

    test('a clock moved backwards does not block forever', () async {
      final c = await container();
      final notifier = await submitted(c);
      now = _start.subtract(const Duration(days: 1));
      await notifier.check();
      expect(stateOf(c).blocksSend, isFalse);
    });

    test('unreadable saved data does not block', () async {
      for (final bad in ['not json', '{"phase":"nope"}', '[]']) {
        storage.pendingSend = bad;
        final c = await container();
        await started(c);
        expect(stateOf(c).send, isNull, reason: bad);
        expect(stateOf(c).blocksSend, isFalse, reason: bad);
      }
    });

    test('storage that throws does not block', () async {
      storage = _ThrowingStorage();
      final c = await container();
      await started(c);
      expect(stateOf(c).blocksSend, isFalse);
    });

    test('a saved send only blocks while it is waiting', () async {
      final c = await container();
      final notifier = await submitted(c);
      await notifier.dismiss();
      expect(
        stateOf(c).send,
        isNotNull,
        reason: 'waiting rows are not dismissible',
      );
      now = _start.add(pendingSendTimeLimit);
      await notifier.check();
      await notifier.dismiss();
      expect(stateOf(c).send, isNull);
      expect(storage.pendingSend, isNull);
    });
  });

  test('the emergency wipe removes the saved send', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    const real = WalletSecureStorage();
    await real.savePendingSend('saved');
    expect(await real.getPendingSend(), 'saved');
    await real.clearWalletData();
    expect(await real.getPendingSend(), isNull);
  });

  group('survives a restart', () {
    test('a pending send comes back, still blocking', () async {
      final first = await container();
      await submitted(first);
      first.dispose();

      final second = await container();
      await started(second);
      final send = stateOf(second).send!;
      expect(send.phase, PendingSendPhase.submitted);
      expect(send.amountBaseUnits, '50000000');
      expect(send.to, _to);
      expect(send.nonce, '7');
      expect(send.hash, _hash);
      expect(stateOf(second).blocksSend, isTrue);
    });

    test(
      'a send confirmed while the app was closed shows as confirmed',
      () async {
        final first = await container();
        await submitted(first);
        first.dispose();

        repository
          ..accountNonceResult = const Right('8')
          ..includedBlockResult = const Right(4242);
        final second = await container();
        await started(second);
        expect(stateOf(second).send!.phase, PendingSendPhase.included);

        final third = await container();
        await started(third);
        expect(stateOf(third).send!.phase, PendingSendPhase.included);
        expect(stateOf(third).send!.blockHeight, 4242);
      },
    );

    test('an app killed mid-post reads back as unknown, not as sent', () async {
      final first = await container();
      await first
          .read(pendingSendProvider.notifier)
          .begin(from: _wallet, to: _to, amountBaseUnits: '1', nonce: '7');
      first.dispose();

      final second = await container();
      await started(second);
      expect(stateOf(second).send!.phase, PendingSendPhase.outcomeUnknown);
      expect(stateOf(second).blocksSend, isTrue);
    });

    test('a limit that passed while closed is honoured on open', () async {
      final first = await container();
      await submitted(first);
      first.dispose();

      now = _start.add(const Duration(hours: 3));
      final second = await container();
      await second.read(pendingSendProvider.notifier).ready;
      expect(stateOf(second).overdue, isTrue);
      expect(stateOf(second).blocksSend, isFalse);
    });

    test("another wallet's send is dropped, not shown", () async {
      final first = await container();
      await submitted(first);
      first.dispose();

      final second = await container(
        wallet: '0x9999999999999999999999999999999999999999',
      );
      await started(second);
      expect(stateOf(second).send, isNull);
      expect(storage.pendingSend, isNull);
    });
  });

  group('a failed post', () {
    test('a refusal leaves no row', () async {
      final c = await container();
      final notifier = c.read(pendingSendProvider.notifier);
      await notifier.begin(
        from: _wallet,
        to: _to,
        amountBaseUnits: '1',
        nonce: '7',
      );
      await notifier.markFailed(const ServerFailure('no', statusCode: 400));
      expect(stateOf(c).send, isNull);
      expect(storage.pendingSend, isNull);
    });

    test('a 409 does not erase the overdue send it conflicts with', () async {
      final c = await container();
      final notifier = await submitted(c);
      now = _start.add(pendingSendTimeLimit);
      await notifier.check();
      expect(stateOf(c).blocksSend, isFalse);

      await notifier.begin(
        from: _wallet,
        to: '0x3333333333333333333333333333333333333333',
        amountBaseUnits: '1',
        nonce: '7',
      );
      await notifier.markFailed(
        const ServerFailure(pendingTransferMessage, statusCode: 409),
      );
      expect(stateOf(c).send!.to, _to);
      expect(stateOf(c).send!.hash, _hash);
    });

    for (final failure in <Failure>[
      const NetworkFailure(),
      const ServerFailure('Server took too long to respond.'),
      const ServerFailure('Server error.'),
      const ServerFailure('timeout', statusCode: 408),
    ]) {
      test('no clear answer (${failure.message}) stays as unknown', () async {
        final c = await container();
        final notifier = c.read(pendingSendProvider.notifier);
        await notifier.begin(
          from: _wallet,
          to: _to,
          amountBaseUnits: '1',
          nonce: '7',
        );
        await notifier.markFailed(failure);
        expect(stateOf(c).send!.phase, PendingSendPhase.outcomeUnknown);
        expect(stateOf(c).blocksSend, isTrue);
      });
    }

    test('an unknown send never reads as confirmed without an id', () async {
      final c = await container();
      final notifier = c.read(pendingSendProvider.notifier);
      await notifier.begin(
        from: _wallet,
        to: _to,
        amountBaseUnits: '1',
        nonce: '7',
      );
      await notifier.markFailed(const NetworkFailure());
      repository
        ..accountNonceResult = const Right('8')
        ..includedBlockResult = const Right(4242);
      await notifier.check();
      expect(stateOf(c).send!.phase, PendingSendPhase.nonceUsedUnmatched);
      expect(stateOf(c).blocksSend, isFalse);
    });

    test('sendDefinitelyRefused sorts answers from non-answers', () {
      for (final refused in <Failure>[
        const AuthFailure(),
        const ValidationFailure('bad'),
        const NotAvailableFailure('off'),
        const ServerFailure('conflict', statusCode: 409),
        const ServerFailure('limit', statusCode: 429),
      ]) {
        expect(sendDefinitelyRefused(refused), isTrue, reason: refused.message);
      }
      expect(sendDefinitelyRefused(StateError('?')), isFalse);
      expect(sendDefinitelyRefused(const NetworkFailure()), isFalse);
    });
  });
}

class _ThrowingStorage extends FakeWalletSecureStorage {
  @override
  Future<String?> getPendingSend() async => throw StateError('locked');
  @override
  Future<void> savePendingSend(String? encoded) async =>
      throw StateError('locked');
}
