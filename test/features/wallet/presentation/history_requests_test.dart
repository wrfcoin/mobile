import 'dart:async';

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

const paid = TransactionModel(
  hash: '',
  eventId: 'contribution:paid',
  from: '',
  type: 'weather_reward',
  direction: 'incoming',
  settlement: 'paid',
  value: '100000000',
);
const operation = TransactionModel(
  hash: 'commit',
  from: 'wallet',
  type: 'ContributionCommit',
);
TransactionPage page({
  List<TransactionModel> credits = const [],
  List<TransactionModel> items = const [operation],
}) => TransactionPage(
  items: items,
  credits: credits,
  offset: 0,
  limit: 20,
  complete: false,
);

typedef Respond = Future<TransactionPage> Function(int, CancelToken?);

class RecordingRepository extends FakeWalletRepository {
  RecordingRepository(this.respond);
  final Respond respond;
  int calls = 0;
  int active = 0;
  int maxActive = 0;
  final offsets = <int>[];
  final tokens = <CancelToken?>[];
  @override
  Future<Either<Failure, TransactionPage>> getTransactions(
    String address, {
    int offset = 0,
    int limit = 20,
    String? creditAfter,
    CancelToken? cancelToken,
  }) async {
    final call = ++calls;
    offsets.add(offset);
    tokens.add(cancelToken);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      return Right(await respond(call, cancelToken));
    } finally {
      active--;
    }
  }
}

Future<ProviderContainer> setup(RecordingRepository repo) async {
  final storage = InMemoryKeyValueStorage();
  await storage.write(key: 'wrf_address', value: 'wrf1testwallet');
  return ProviderContainer(
    overrides: [
      walletRepositoryProvider.overrideWithValue(repo),
      keyManagerProvider.overrideWithValue(
        KeyManager(
          biometric: BiometricService(client: FakeLocalAuthClient()),
          storage: storage,
        ),
      ),
    ],
  );
}

Future<void> settle() async {
  for (var i = 0; i < 70; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'leaving history cancels the read when its last listener goes',
    () async {
      final repo = RecordingRepository((call, token) async {
        await token!.whenCancel;
        return page();
      });
      final container = await setup(repo);
      addTearDown(container.dispose);
      final subscription = container.listen(transactionsProvider, (_, _) {});
      await settle();
      expect(repo.calls, 1);
      subscription.close();
      await container.pump();
      await settle();
      expect(repo.tokens.last!.isCancelled, true);
      expect(repo.active, 0);
    },
  );

  test('no more reward records: nothing is said to be missing', () async {
    final repo = RecordingRepository(
      (call, token) async => page(credits: [paid]),
    );
    final container = await setup(repo);
    addTearDown(container.dispose);
    container.listen(transactionsProvider, (_, _) {});
    final state = await container.read(transactionsProvider.future);
    expect(state.creditsTruncated, false);
    expect(state.credits, [paid]);
  });

  test('refresh cancels the old read and discards its answer', () async {
    final repo = RecordingRepository((call, token) async {
      if (call == 1) return page();
      if (call == 2) {
        await token!.whenCancel;
        return page(credits: [paid]);
      }
      return page();
    });
    final container = await setup(repo);
    addTearDown(container.dispose);
    container.listen(transactionsProvider, (_, _) {});
    await container.read(transactionsProvider.future);
    final notifier = container.read(transactionsProvider.notifier);
    // A build that a refresh supersedes while its read is still running.
    container.invalidate(transactionsProvider);
    await settle();
    await notifier.refresh();
    await settle();
    expect(repo.calls, 3);
    expect(repo.maxActive, 1);
    expect(container.read(transactionsProvider).requireValue.credits, isEmpty);
  });

  test('load-more cannot race another load-more', () async {
    final pending = Completer<TransactionPage>();
    TransactionPage withMore() => TransactionPage(
      items: const [operation],
      offset: 0,
      limit: 50,
      totalInWindow: 500,
    );
    final repo = RecordingRepository(
      (call, token) async => call == 1 ? withMore() : pending.future,
    );
    final container = await setup(repo);
    addTearDown(container.dispose);
    container.listen(transactionsProvider, (_, _) {});
    await container.read(transactionsProvider.future);
    final notifier = container.read(transactionsProvider.notifier);
    final loads = [notifier.loadMore(), notifier.loadMore()];
    await settle();
    expect(repo.calls, 2);
    expect(repo.offsets, [0, TransactionsNotifier.pageSize]);
    pending.complete(
      const TransactionPage(items: [], offset: 50, limit: 50, totalInWindow: 1),
    );
    await Future.wait(loads);
    expect(repo.maxActive, 1);
  });

  test('the page size is within what the public edge admits', () {
    expect(TransactionsNotifier.pageSize, lessThanOrEqualTo(50));
  });
}
