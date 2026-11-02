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
  String? cursor,
  List<TransactionModel> credits = const [],
  List<TransactionModel> items = const [operation],
}) => TransactionPage(
  items: items,
  credits: credits,
  creditNextCursor: cursor,
  offset: 0,
  limit: 20,
  complete: false,
);

/// A cursor the public edge admits, as the node sends them.
String c(Object seed) =>
    seed.hashCode.toRadixString(16).padLeft(8, '0').padRight(64, 'a');

typedef Respond = Future<TransactionPage> Function(int, String?, CancelToken?);

class RecordingRepository extends FakeWalletRepository {
  RecordingRepository(this.respond);
  final Respond respond;
  int calls = 0;
  int active = 0;
  int maxActive = 0;
  final offsets = <int>[];
  final cursors = <String?>[];
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
    cursors.add(creditAfter);
    tokens.add(cancelToken);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      return Right(await respond(call, creditAfter, cancelToken));
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
    'leaving history cancels scanning when its last listener is removed',
    () async {
      final repo = RecordingRepository((call, cursor, token) async {
        if (call == 1) return page(cursor: c('next'));
        await token!.whenCancel;
        return page(cursor: c('must-not-fetch'));
      });
      final container = await setup(repo);
      addTearDown(container.dispose);
      final subscription = container.listen(transactionsProvider, (_, _) {});
      await container.read(transactionsProvider.future);
      await settle();
      expect(repo.calls, 2);
      subscription.close();
      await container.pump();
      await settle();
      expect(repo.tokens.last!.isCancelled, true);
      expect(repo.calls, 2);
      expect(repo.active, 0);
    },
  );

  test(
    'initial scan stops at first credits without advancing transaction offset',
    () async {
      final repo = RecordingRepository(
        (call, cursor, token) async => call < 3
            ? page(cursor: c(call))
            : page(cursor: c(3), credits: [paid]),
      );
      final container = await setup(repo);
      addTearDown(container.dispose);
      final sub = container.listen(transactionsProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(transactionsProvider.future);
      await settle();
      final state = container.read(transactionsProvider).requireValue;
      expect(repo.calls, 3);
      expect(repo.cursors, [null, c(1), c(2)]);
      expect(repo.offsets, [0, 0, 0]);
      expect(repo.maxActive, 1);
      expect(state.credits, [paid]);
      expect(state.items, [operation]);
      expect(state.discoveringCredits, false);
      await container.read(transactionsProvider.notifier).loadMore();
      expect(repo.offsets.last, TransactionsNotifier.pageSize);
      expect(repo.cursors.last, c(3));
      expect(container.read(transactionsProvider).requireValue.credits, [paid]);
    },
  );
  test(
    'scan includes initial page in its bound and preserves incomplete history',
    () async {
      final repo = RecordingRepository(
        (call, cursor, token) async => page(cursor: c(call)),
      );
      final container = await setup(repo);
      addTearDown(container.dispose);
      container.listen(transactionsProvider, (_, _) {});
      await container.read(transactionsProvider.future);
      await settle();
      final state = container.read(transactionsProvider).requireValue;
      expect(repo.calls, TransactionsNotifier.maxCreditDiscoveryPages);
      expect(repo.maxActive, 1);
      expect(state.discoveringCredits, false);
      expect(state.creditsTruncated, true);
      expect(state.complete, false);
      expect(state.hasMore, true, reason: 'Load more carries on from here');
      expect(
        state.creditNextCursor,
        c(TransactionsNotifier.maxCreditDiscoveryPages),
      );
      await settle();
      expect(repo.calls, TransactionsNotifier.maxCreditDiscoveryPages);
    },
  );
  test(
    'refresh repeats discovery and concurrent refreshes are coalesced',
    () async {
      final repo = RecordingRepository(
        (call, cursor, token) async =>
            cursor == null ? page(cursor: c('next')) : page(credits: [paid]),
      );
      final container = await setup(repo);
      addTearDown(container.dispose);
      container.listen(transactionsProvider, (_, _) {});
      await container.read(transactionsProvider.future);
      await settle();
      final notifier = container.read(transactionsProvider.notifier);
      await Future.wait([notifier.refresh(), notifier.refresh()]);
      expect(repo.calls, 4);
      expect(repo.cursors, [null, c('next'), null, c('next')]);
      expect(repo.maxActive, 1);
      expect(container.read(transactionsProvider).requireValue.credits, [paid]);
    },
  );
  test(
    'dispose cancels an in-flight discovery request and sends no next page',
    () async {
      final repo = RecordingRepository((call, cursor, token) async {
        if (call == 1) return page(cursor: c('next'));
        await token!.whenCancel;
        return page(cursor: c('must-not-fetch'));
      });
      final container = await setup(repo);
      container.listen(transactionsProvider, (_, _) {});
      await container.read(transactionsProvider.future);
      await settle();
      expect(repo.calls, 2);
      expect(repo.active, 1);
      container.dispose();
      await settle();
      expect(repo.tokens.last!.isCancelled, true);
      expect(repo.calls, 2);
      expect(repo.active, 0);
    },
  );
  test('refresh cancels old scan, serializes replacement and discards stale credit', () async {
    final repo = RecordingRepository((call, cursor, token) async {
      if (call == 1) return page(cursor: c('old'));
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
    await settle();
    await container.read(transactionsProvider.notifier).refresh();
    await settle();
    expect(repo.calls, 3);
    expect(repo.maxActive, 1);
    expect(container.read(transactionsProvider).requireValue.credits, isEmpty);
  });
  test('load-more cannot race discovery or another load-more', () async {
    final pending = Completer<TransactionPage>();
    final repo = RecordingRepository(
      (call, cursor, token) async => call == 1
          ? page(cursor: c('next'))
          : call == 2
          ? pending.future
          : page(),
    );
    final container = await setup(repo);
    addTearDown(container.dispose);
    container.listen(transactionsProvider, (_, _) {});
    await container.read(transactionsProvider.future);
    await settle();
    final notifier = container.read(transactionsProvider.notifier);
    await Future.wait([notifier.loadMore(), notifier.loadMore()]);
    expect(repo.calls, 2);
    pending.complete(page(cursor: c('more'), credits: [paid]));
    await settle();
    await Future.wait([notifier.loadMore(), notifier.loadMore()]);
    expect(repo.calls, 3);
    expect(repo.maxActive, 1);
  });
  test(
    'a repeated credit cursor stops discovery without a request loop',
    () async {
      final repo = RecordingRepository(
        (call, cursor, token) async => page(cursor: c('same')),
      );
      final container = await setup(repo);
      addTearDown(container.dispose);
      container.listen(transactionsProvider, (_, _) {});
      await container.read(transactionsProvider.future);
      await settle();
      expect(repo.calls, 2);
      expect(
        container.read(transactionsProvider).requireValue.discoveringCredits,
        false,
      );
    },
  );
  test(
    'a non-adjacent A B A cursor cycle stops after three requests',
    () async {
      final repo = RecordingRepository(
        (call, cursor, token) async => page(cursor: c(call.isOdd ? 'A' : 'B')),
      );
      final container = await setup(repo);
      addTearDown(container.dispose);
      container.listen(transactionsProvider, (_, _) {});
      await container.read(transactionsProvider.future);
      await settle();
      final state = container.read(transactionsProvider).requireValue;
      expect(repo.calls, 3);
      expect(repo.cursors, [null, c('A'), c('B')]);
      expect(repo.maxActive, 1);
      expect(state.discoveringCredits, false);
      expect(state.creditNextCursor, isNull);
      expect(state.creditsTruncated, true);
      await settle();
      expect(repo.calls, 3);
    },
  );

  test('a cursor the edge would refuse is never read', () async {
    final repo = RecordingRepository(
      (call, cursor, token) async => page(cursor: 'commit&first'),
    );
    final container = await setup(repo);
    addTearDown(container.dispose);
    container.listen(transactionsProvider, (_, _) {});
    final state = await container.read(transactionsProvider.future);
    await settle();
    expect(repo.calls, 1);
    expect(state.creditNextCursor, isNull);
    expect(state.discoveringCredits, false);
    expect(state.creditsTruncated, true);
  });

  test('a failed search keeps the list, and Load more carries on', () async {
    final repo = RecordingRepository((call, cursor, token) async {
      if (call == 1) return page(cursor: c(1));
      if (call == 2) throw const ServerFailure('busy');
      return page(credits: [paid]);
    });
    final container = await setup(repo);
    addTearDown(container.dispose);
    container.listen(transactionsProvider, (_, _) {});
    await container.read(transactionsProvider.future);
    await settle();
    final state = container.read(transactionsProvider).requireValue;
    expect(state.items, [operation]);
    expect(state.discoveringCredits, false);
    expect(state.creditsTruncated, true);
    expect(state.hasMore, true);

    await container.read(transactionsProvider.notifier).loadMore();
    final after = container.read(transactionsProvider).requireValue;
    expect(repo.cursors, [null, c(1), c(1)]);
    expect(after.credits, [paid]);
    expect(after.creditsTruncated, false, reason: 'the last page ended them');
  });
}
