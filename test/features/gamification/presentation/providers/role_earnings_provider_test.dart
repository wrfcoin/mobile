import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/role_earnings_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/role_earnings_repository.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/providers/role_earnings_provider.dart';

import '../../../../fixtures/role_earnings_fixture.dart';

class PendingRepository extends RoleEarningsRepository {
  PendingRepository() : super(Dio());
  final pending = <Completer<RoleLeaderboard>>[];
  @override
  Future<RoleLeaderboard> leaderboard(
    EarningsRole role,
    EarningsPeriod period,
  ) {
    final c = Completer<RoleLeaderboard>();
    pending.add(c);
    return c.future;
  }
}

void main() {
  test(
    'switch clears rows; older completion cannot overwrite newer role/period',
    () async {
      final repo = PendingRepository();
      final c = ProviderContainer(
        overrides: [
          roleEarningsRepositoryProvider.overrideWithValue(repo),
          earningsReadProvider.overrideWith((ref) async => true),
        ],
      );
      addTearDown(c.dispose);
      final notifier = c.read(roleBoardProvider.notifier);
      final first = notifier.load();
      await Future<void>.delayed(Duration.zero);
      final second = notifier.load(
        role: EarningsRole.attester,
        period: EarningsPeriod.sevenDays,
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.read(roleBoardProvider).board, isNull);
      final body = roleBoard('attester')
        ..['requestedScope'] = '7d'
        ..['effectiveScope'] = '7d';
      body['window']['from'] = '2026-10-04T12:00:00.000001Z';
      repo.pending[1].complete(
        RoleLeaderboard.parse(
          body,
          EarningsRole.attester,
          EarningsPeriod.sevenDays,
        ),
      );
      await second;
      repo.pending[0].complete(
        RoleLeaderboard.parse(
          roleBoard('producer'),
          EarningsRole.producer,
          EarningsPeriod.all,
        ),
      );
      await first;
      expect(c.read(roleBoardProvider).board!.role, EarningsRole.attester);
      expect(c.read(roleBoardProvider).period, EarningsPeriod.sevenDays);
      final third = notifier.load();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(roleBoardProvider).board, isNull);
      repo.pending[2].completeError(const FormatException('synthetic failure'));
      await third;
      expect(c.read(roleBoardProvider).failed, isTrue);
      expect(c.read(roleBoardProvider).board, isNull);
      final retry = notifier.load();
      await Future<void>.delayed(Duration.zero);
      repo.pending[3].complete(
        RoleLeaderboard.parse(
          body,
          EarningsRole.attester,
          EarningsPeriod.sevenDays,
        ),
      );
      await retry;
      expect(c.read(roleBoardProvider).failed, isFalse);
    },
  );
  test('OFF never calls the earnings repository', () async {
    final repo = PendingRepository();
    final c = ProviderContainer(
      overrides: [
        roleEarningsRepositoryProvider.overrideWithValue(repo),
        earningsReadProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(c.dispose);
    await c.read(roleBoardProvider.notifier).load();
    expect(repo.pending, isEmpty);
  });
}
