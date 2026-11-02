// The node reads reward records for the whole chain, ordered by commit ID, and
// keeps this wallet's after the read (core4 `paid_credit_page`). So a read can
// come back with none of this wallet's rewards and still have more behind it.
// One tap of Load more has to mean a page of rows, not one read of the chain.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_page.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../../test_helpers/fakes.dart';

String _commitId(int index) => index.toRadixString(16).padLeft(64, '0');

TransactionModel _reward(int index) => TransactionModel(
  hash: '',
  eventId: 'contribution:${_commitId(index)}',
  from: '',
  type: 'weather_reward',
  direction: 'incoming',
  settlement: 'paid',
  value: '100000000',
);

/// What core4 answers: [creditLimit] chain-wide records per read, then a filter
/// to this wallet, with a cursor whenever records remain.
class _Node extends FakeWalletRepository {
  _Node({required this.records, required this.everyNth, this.failAfterReads});

  static const creditLimit = 100;
  final int records;
  final int everyNth;
  final int? failAfterReads;
  int reads = 0;

  bool _mine(int index) => index % everyNth == 0;

  @override
  Future<Either<Failure, TransactionPage>> getTransactions(
    String address, {
    int offset = 0,
    int limit = 20,
    String? creditAfter,
    CancelToken? cancelToken,
  }) async {
    reads++;
    if (failAfterReads != null && reads > failAfterReads!) {
      return const Left(ServerFailure('busy'));
    }
    final start = creditAfter == null
        ? 0
        : int.parse(creditAfter, radix: 16) + 1;
    final end = start + creditLimit;
    return Right(
      TransactionPage(
        items: const [],
        credits: [
          for (var i = start; i < end && i < records; i++)
            if (_mine(i)) _reward(i),
        ],
        creditNextCursor: end < records ? _commitId(end - 1) : null,
        offset: offset,
        limit: limit,
      ),
    );
  }
}

Future<ProviderContainer> _open(_Node node) async {
  final storage = InMemoryKeyValueStorage();
  await storage.write(key: 'wrf_address', value: 'wrf1testwallet');
  final container = ProviderContainer(
    overrides: [
      walletRepositoryProvider.overrideWithValue(node),
      keyManagerProvider.overrideWithValue(
        KeyManager(
          biometric: BiometricService(client: FakeLocalAuthClient()),
          storage: storage,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(transactionsProvider, (_, _) {});
  await container.read(transactionsProvider.future);
  return container;
}

void main() {
  test(
    'one tap adds a full page, however sparse this wallet\'s rewards',
    () async {
      // One of this wallet's rewards per 200 records: reward 0 is on the first
      // read, so nothing searches in the background.
      final node = _Node(records: 40000, everyNth: 200);
      final container = await _open(node);
      final notifier = container.read(transactionsProvider.notifier);
      int shown() =>
          container.read(transactionsProvider).requireValue.credits.length;

      final addedPerTap = <int>[];
      for (var tap = 0; tap < 4; tap++) {
        final before = shown();
        await notifier.loadMore();
        addedPerTap.add(shown() - before);
      }
      // Before the fix this was [0, 1, 0, 1]: tap, nothing; tap, one more.
      expect(addedPerTap, everyElement(greaterThan(1)));
      expect(addedPerTap, isNot(contains(0)));
    },
  );

  test('a tap stops as soon as it has a page', () async {
    // Every record is this wallet's: one read is already a full page.
    final node = _Node(records: 1000, everyNth: 1);
    final container = await _open(node);
    final readsBefore = node.reads;
    await container.read(transactionsProvider.notifier).loadMore();
    expect(node.reads - readsBefore, 1);
  });

  test('a tap reads to the end when fewer than a page remain', () async {
    final node = _Node(records: 900, everyNth: 200);
    final container = await _open(node);
    await container.read(transactionsProvider.notifier).loadMore();
    final state = container.read(transactionsProvider).requireValue;
    expect(state.credits, hasLength(5));
    expect(state.hasMore, isFalse);
    expect(state.creditsTruncated, isFalse);
  });

  test('a tap stops at its read limit and says nothing was found', () async {
    // Reward 0, then nothing anywhere in the next reads.
    final node = _Node(records: 90000, everyNth: 80000);
    final container = await _open(node);
    final readsBefore = node.reads;
    await container.read(transactionsProvider.notifier).loadMore();
    final state = container.read(transactionsProvider).requireValue;
    expect(node.reads - readsBefore, TransactionsNotifier.maxReadsPerLoad);
    expect(state.loadingMore, isFalse);
    expect(state.hasMore, isTrue, reason: 'the next tap carries on');
    expect(state.lastLoadFoundNothing, isTrue);
  });

  test('a read that fails partway keeps what it found, and the next tap carries on', () async {
    final node = _Node(records: 40000, everyNth: 200, failAfterReads: 5);
    final container = await _open(node);
    await container.read(transactionsProvider.notifier).loadMore();
    final state = container.read(transactionsProvider);
    expect(state.hasError, isFalse);
    expect(state.requireValue.credits.length, greaterThan(1));
    expect(state.requireValue.loadingMore, isFalse);
    expect(state.requireValue.hasMore, isTrue);
  });

  test('a tap stays within the edge budget of 30 reads a minute', () {
    expect(TransactionsNotifier.maxReadsPerLoad, lessThan(15));
    expect(TransactionsNotifier.maxCreditDiscoveryPages, lessThan(15));
  });

  test('a first read that fails keeps the list and says so', () async {
    final node = _Node(records: 40000, everyNth: 200, failAfterReads: 1);
    final container = await _open(node);
    await container.read(transactionsProvider.notifier).loadMore();
    final state = container.read(transactionsProvider);
    expect(state.hasError, isFalse);
    expect(state.requireValue.credits, hasLength(1));
    expect(state.requireValue.lastLoadFailed, isTrue);
    expect(state.requireValue.hasMore, isTrue);
  });
}
