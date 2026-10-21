import 'package:wrfcoin_mobile/features/gamification/data/models/role_earnings_model.dart';

import '../../../../fixtures/role_earnings_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/leaderboard_entry_model.dart';

void main() {
  test('B2 lossless amount and server own-row privacy', () {
    final board = RoleLeaderboard.parse(
      roleBoard('producer'),
      EarningsRole.producer,
      EarningsPeriod.all,
    );
    expect(board.rows.single.amount, '90071992.54741000');
    expect(board.rows.single.shortAddress, '0x0000…0001');
    expect(board.rows.single.isYou, isTrue);
    expect(OwnRoleEarnings.parse(roleFixture()['ownProfile']).roles.length, 5);
  });
  for (final change in <String, dynamic>{
    'units': {'currency': 'OTHER', 'decimals': 8, 'scale': '100000000'},
    'complete': false,
    'effectiveScope': '7d',
    'role': 'attester',
    'coverage': {'fromHeight': '2', 'throughHeight': '4', 'complete': true},
    'asOf': null,
    'finalityPolicy': 'unknown',
  }.entries) {
    test('B2 rejects unproven ${change.key}', () {
      final body = roleBoard('producer')..[change.key] = change.value;
      expect(
        () => RoleLeaderboard.parse(
          body,
          EarningsRole.producer,
          EarningsPeriod.all,
        ),
        throwsA(isA<Exception>()),
      );
    });
  }
  for (final field in ['paidBaseUnits', 'paidDisplay', 'shortAddress']) {
    test('B2 rejects unsafe row $field', () {
      final body = roleBoard('producer');
      body['rows'][0][field] = field == 'shortAddress'
          ? '0x0000000000000000000000000000000000000001'
          : 'bad';
      expect(
        () => RoleLeaderboard.parse(
          body,
          EarningsRole.producer,
          EarningsPeriod.all,
        ),
        throwsA(isA<Exception>()),
      );
    });
  }
  test('B2 profile fails closed without authenticated ownership', () {
    final body = roleFixture()['ownProfile'];
    body['profile']['isYou'] = false;
    expect(() => OwnRoleEarnings.parse(body), throwsA(isA<Exception>()));
  });

  earningsEntryTests();
  group('LeaderboardEntry.fromJson', () {
    test('parses complete JSON', () {
      final entry = LeaderboardEntry.fromJson({
        'rank': 1,
        'name': 'Alice',
        'readings': 500,
        'region': 'North America',
      }, 0);

      expect(entry.rank, 1);
      expect(entry.name, 'Alice');
      expect(entry.score, '500');
      expect(entry.metricLabel, 'readings');
      expect(entry.subtitle, 'North America');
    });

    test('uses index+1 as fallback rank', () {
      final entry = LeaderboardEntry.fromJson({'name': 'Bob'}, 4);

      expect(entry.rank, 5);
    });

    test('provides defaults for missing fields', () {
      final entry = LeaderboardEntry.fromJson({}, 0);

      expect(entry.rank, 1);
      expect(entry.name, 'Unknown');
      expect(entry.score, '0');
      expect(entry.metricLabel, 'score');
      expect(entry.subtitle, '');
    });

    test('maps achievement leaderboard payloads', () {
      final entry = LeaderboardEntry.fromJson({
        'username': 'WeatherMaster',
        'completedAchievements': 12,
        'badges': const ['weather_gold', 'mining_silver'],
      }, 1);

      expect(entry.rank, 2);
      expect(entry.name, 'WeatherMaster');
      expect(entry.score, '12');
      expect(entry.metricLabel, 'achievements');
      expect(entry.subtitle, '2 badges');
    });
  });
}

// ── #409: chain-earnings board rows ─────────────────────────────────────────
void earningsEntryTests() {
  group('LeaderboardEntry.fromJson (earnings board)', () {
    Map<String, dynamic> row(Object? units, {bool isYou = false}) => {
      'rank': 2,
      'displayName': 'Station Alpha',
      'walletAddress': isYou
          ? '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
          : '0xaaaa…aaaa',
      'isYou': isYou,
      'earningsBaseUnits': units,
      'earningsWrf': '1.5',
      'profileKey': 'pk',
      'value': 12,
    };

    test('formats base units exactly to 8 decimals', () {
      final e = LeaderboardEntry.fromJson(row('150000000'), 0);
      expect(e.rank, 2);
      expect(e.name, 'Station Alpha');
      expect(e.score, '1.50000000');
      expect(e.metricLabel, 'WRF');
      expect(e.isYou, isFalse);
    });

    test('is exact beyond double precision', () {
      final e = LeaderboardEntry.fromJson(row('9007199254740993123'), 0);
      expect(e.score, '90071992547.40993123');
    });

    test('formats zero and sub-WRF amounts', () {
      expect(LeaderboardEntry.fromJson(row('0'), 0).score, '0.00000000');
      expect(LeaderboardEntry.fromJson(row('1'), 0).score, '0.00000001');
    });

    test('rejects malformed or null amounts rather than showing zero', () {
      for (final bad in <Object?>[null, '', '-5', '1.5', 'abc', 12]) {
        expect(
          () => LeaderboardEntry.fromJson(row(bad), 0),
          throwsFormatException,
          reason: 'amount $bad',
        );
      }
    });

    test('shows the address exactly as served and flags own row', () {
      final anon = LeaderboardEntry.fromJson(row('1'), 0);
      expect(anon.subtitle, '0xaaaa…aaaa');
      final me = LeaderboardEntry.fromJson(row('1', isYou: true), 0);
      expect(me.isYou, isTrue);
      expect(me.subtitle, '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    });
  });
}
