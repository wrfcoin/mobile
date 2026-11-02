/// Test fixtures. The empty answers are the live routes' real answers on
/// 2026-11-02; the loaded answers follow backend competition-routes.ts and
/// their addresses are made up.
const _rule = {
  'id': 'scored-forecasts-v1',
  'points': 'One point for each of your forecasts that the chain scored and decided a reward for during the week.',
  'ties': 'Equal points: whoever reached the total first ranks higher.',
  'prizes': 'Points only. No WRF is paid and nothing is staked.',
  'week':
      'Weeks run Monday 00:00 UTC to the next Monday 00:00 UTC, by block time.',
};

const _asOf = {
  'height': '11598',
  'hash': 'cb38',
  'time': '2026-11-02T01:40:47.000000Z',
  'checkedAt': '2026-11-02T01:41:23.098Z',
};

const emptyWeeks = <String, dynamic>{
  'success': true,
  'current': '2026-W45',
  'weeks': [
    {
      'week': '2026-W45',
      'from': '2026-11-02T00:00:00.000Z',
      'until': '2026-11-09T00:00:00.000Z',
      'title': 'Week 45, 2026 forecast competition',
      'status': 'open',
      'entrants': 0,
      'forecasts': '0',
      'leaders': <Object>[],
    },
    {
      'week': '2026-W44',
      'from': '2026-10-26T00:00:00.000Z',
      'until': '2026-11-02T00:00:00.000Z',
      'title': 'Week 44, 2026 forecast competition',
      'status': 'final',
      'entrants': 0,
      'forecasts': '0',
      'leaders': <Object>[],
    },
  ],
};

const emptyCurrent = <String, dynamic>{
  'success': true,
  'competition': {
    'week': '2026-W45',
    'from': '2026-11-02T00:00:00.000Z',
    'until': '2026-11-09T00:00:00.000Z',
    'title': 'Week 45, 2026 forecast competition',
    'status': 'open',
    'rule': _rule,
    'final': null,
  },
  'asOf': _asOf,
  'coverage': {
    'fromHeight': '1',
    'throughHeight': '11598',
    'complete': true,
    'skippedRecords': '0',
  },
  'entrants': 0,
  'forecasts': '0',
  'rows': <Object>[],
  'you': null,
  'limit': 50,
};

Map<String, dynamic> row(
  int rank,
  String points, {
  String? address,
  bool isYou = false,
}) => {
  'rank': rank,
  'points': points,
  'forecasts': points,
  'firstAt': '2026-11-02T03:00:00.000000Z',
  'lastAt': '2026-11-03T18:30:00.000000Z',
  'profileKey': 'c_key$rank',
  'shortAddress': '0xab${rank}0…12$rank',
  'address': address,
  'isYou': isYou,
};

final loadedCurrent = <String, dynamic>{
  ...emptyCurrent,
  'entrants': 12,
  'forecasts': '1234',
  'rows': [row(1, '1000'), row(2, '200'), row(3, '30'), row(4, '4')],
};

final loadedWithYouBelow = <String, dynamic>{
  ...loadedCurrent,
  'you': row(77, '1', address: '0x${'ab' * 20}', isYou: true),
};

final loadedWeeks = <String, dynamic>{
  'success': true,
  'current': '2026-W45',
  'weeks': [
    (emptyWeeks['weeks'] as List).first,
    {
      'week': '2026-W44',
      'from': '2026-10-26T00:00:00.000Z',
      'until': '2026-11-02T00:00:00.000Z',
      'title': 'Week 44, 2026 forecast competition',
      'status': 'final',
      'entrants': 3,
      'forecasts': '9',
      'leaders': [row(1, '5')],
    },
  ],
};

final finalWeek44 = <String, dynamic>{
  'success': true,
  'competition': {
    'week': '2026-W44',
    'from': '2026-10-26T00:00:00.000Z',
    'until': '2026-11-02T00:00:00.000Z',
    'title': 'Week 44, 2026 forecast competition',
    'status': 'final',
    'rule': _rule,
    'final': {
      'finalizedAt': '2026-11-02T01:10:00.000Z',
      'throughHeight': '11500',
      'throughHash': 'ab',
    },
  },
  'asOf': null,
  'coverage': null,
  'entrants': 3,
  'forecasts': '9',
  'rows': [row(1, '5')],
  'you': null,
  'limit': 50,
};
