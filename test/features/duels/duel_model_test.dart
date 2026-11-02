import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/duels/data/models/duel_model.dart';

const _a = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _b = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _c = '0xcccccccccccccccccccccccccccccccccccccccc';

Duel _duel({
  String phase = 'open',
  DuelEntry? creator = const DuelEntry(address: _a),
  DuelEntry? opponent,
  String? invited,
}) => Duel(
  id: '6f1d2c4e-8a8b-4c1e-9d6a-1f2e3d4c5b6a',
  stationAlias: 'st_7d29a4c1e0b8',
  phase: phase,
  creator: creator,
  opponent: opponent,
  invitedOpponent: invited,
);

void main() {
  group('target hours', () {
    test('start on the first whole UTC hour at least 7 hours ahead', () {
      final hours = duelTargetHourOptions(DateTime.utc(2026, 11, 2, 3, 20));
      expect(hours.first, DateTime.utc(2026, 11, 2, 11));
      expect(hours, hasLength(24));
      expect(hours.last, DateTime.utc(2026, 11, 3, 10));
    });

    test('an exact hour stays on it', () {
      final hours = duelTargetHourOptions(DateTime.utc(2026, 11, 2, 3));
      expect(hours.first, DateTime.utc(2026, 11, 2, 10));
    });

    test('a local time gives the same UTC hour', () {
      final now = DateTime.utc(2026, 11, 2, 3, 20);
      expect(
        duelTargetHourOptions(now.toLocal()).first,
        duelTargetHourOptions(now).first,
      );
    });
  });

  group('open request', () {
    final target = DateTime.utc(2026, 11, 2, 11);

    test('matches what the server parses, with no opponent key when open', () {
      expect(
        OpenDuelInput(
          stationAlias: ' ST_7D29A4C1E0B8 ',
          targetAt: target,
          opponent: '  ',
        ).toJson(),
        {
          'stationAlias': 'st_7d29a4c1e0b8',
          'targetAt': '2026-11-02T11:00:00.000Z',
        },
      );
    });

    test('names an opponent when given', () {
      expect(
        OpenDuelInput(
          stationAlias: 'st_7d29a4c1e0b8',
          targetAt: target,
          opponent: ' $_b ',
        ).toJson()['opponent'],
        _b,
      );
    });
  });

  group('record hand-in', () {
    test('takes the fields from commit.json and normalizes data', () {
      final record = DuelRecordInput.parse(
        '{"commit_id":"ABC","nonce":"n1","timestamp":1800000000}',
        '  {"a":1,\r\n"b":2}\r\n',
      );
      expect(record.toJson(), {
        'commitId': 'abc',
        'nonce': 'n1',
        'timestamp': 1800000000,
        'data': '{"a":1,\n"b":2}',
      });
    });

    test('refuses a commit.json that is not a JSON object', () {
      for (final bad in ['not json', '[1,2]', '3']) {
        expect(
          () => DuelRecordInput.parse(bad, '{}'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'commit.json is not valid JSON.',
            ),
          ),
        );
      }
    });
  });

  group('what a wallet may do', () {
    test('another wallet can accept an open duel, its creator cannot', () {
      expect(_duel().canAccept(_b), isTrue);
      expect(_duel().canAccept(_a), isFalse);
      expect(_duel().canAccept(null), isFalse);
      expect(_duel(phase: 'expired').canAccept(_b), isFalse);
    });

    test('an invited duel is only for the invited wallet', () {
      expect(_duel(invited: _b).canAccept(_b), isTrue);
      expect(_duel(invited: _b).canAccept(_c), isFalse);
    });

    test('a player links once, before the lock', () {
      final both = _duel(
        phase: 'committing',
        opponent: const DuelEntry(address: _b, commitId: 'c1'),
      );
      expect(both.canLink(_a), isTrue);
      expect(both.canLink(_b), isFalse);
      expect(both.canLink(_c), isFalse);
      expect(_duel(phase: 'judging').canLink(_a), isFalse);
    });

    test('records are wanted only for a linked, unproven forecast', () {
      expect(
        _duel(
          phase: 'judging',
          creator: const DuelEntry(address: _a, commitId: 'c1'),
        ).needsRecords,
        isTrue,
      );
      expect(
        _duel(
          phase: 'judging',
          creator: const DuelEntry(
            address: _a,
            commitId: 'c1',
            recordVerified: true,
          ),
        ).needsRecords,
        isFalse,
      );
      expect(_duel(phase: 'judging').needsRecords, isFalse);
      expect(
        _duel(
          phase: 'committing',
          creator: const DuelEntry(address: _a, commitId: 'c1'),
        ).needsRecords,
        isFalse,
      );
    });
  });

  group('reward display', () {
    test('groups the whole part and keeps 8 decimals', () {
      expect(formatWrfBaseUnits('10000000'), '0.10000000 WRF');
      expect(formatWrfBaseUnits('123456700000000'), '1,234,567.00000000 WRF');
      expect(formatWrfBaseUnits('0'), '0.00000000 WRF');
    });

    test('never shows an unreadable amount as a number', () {
      expect(formatWrfBaseUnits(null), isNull);
      expect(formatWrfBaseUnits('-1'), isNull);
      expect(formatWrfBaseUnits('1.5'), isNull);
    });
  });
}
