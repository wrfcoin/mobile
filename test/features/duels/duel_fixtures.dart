/// Duels in the shape backend `duelView` (services/forecast-duels.ts) answers.
const duelIdForTest = '6f1d2c4e-8a8b-4c1e-9d6a-1f2e3d4c5b6a';
const duelWalletA = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const duelWalletB = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, dynamic> _entry(
  String address, {
  String? commitId,
  bool verified = false,
  Map<String, dynamic>? forecast,
  String? reward,
  bool finalized = false,
}) => {
  'address': address,
  'commitId': commitId,
  'linkedAt': commitId == null ? null : '2026-11-02T01:00:00.000Z',
  'recordVerified': verified,
  'modelId': null,
  'forecast': forecast,
  'chainReward': reward,
  'chainRewardFinalized': finalized,
  'status': commitId == null ? 'no_entry' : 'linked',
  'invalidReason': null,
};

Map<String, dynamic> _duel({
  String id = duelIdForTest,
  required String status,
  required String phase,
  required Map<String, dynamic> creator,
  Map<String, dynamic>? opponent,
  String? invited,
  Map<String, dynamic>? outcome,
}) => {
  'id': id,
  'stationAlias': 'st_7d29a4c1e0b8',
  'targetAt': '2026-11-02T11:00:00.000Z',
  'lockAt': '2026-11-02T05:00:00.000Z',
  'resolveBy': '2026-11-04T11:00:00.000Z',
  'status': status,
  'phase': phase,
  'mode': 'free_play',
  'stakes': null,
  'creator': creator,
  'opponent': opponent,
  'invitedOpponent': invited,
  'outcome': outcome,
  'judge': 'The chain.',
  'createdAt': '2026-11-02T00:00:00.000Z',
  'matchedAt': null,
  'resolvedAt': null,
};

Map<String, dynamic> openDuelJson({String? invited}) => _duel(
  status: 'open',
  phase: 'open',
  creator: _entry(duelWalletA),
  invited: invited,
);

Map<String, dynamic> committingDuelJson() => _duel(
  id: '7f1d2c4e-8a8b-4c1e-9d6a-1f2e3d4c5b6a',
  status: 'matched',
  phase: 'committing',
  creator: _entry(duelWalletA),
  opponent: _entry(duelWalletB),
);

Map<String, dynamic> liveDuelJson() => _duel(
  id: '8f1d2c4e-8a8b-4c1e-9d6a-1f2e3d4c5b6a',
  status: 'matched',
  phase: 'judging',
  creator: _entry(duelWalletA, commitId: 'aa' * 32),
  opponent: _entry(duelWalletB, commitId: 'bb' * 32),
);

Map<String, dynamic> finishedDuelJson() => _duel(
  id: '9f1d2c4e-8a8b-4c1e-9d6a-1f2e3d4c5b6a',
  status: 'resolved',
  phase: 'resolved',
  creator: _entry(
    duelWalletA,
    commitId: 'aa' * 32,
    verified: true,
    forecast: {'temperature_c': 12.5},
    reward: '25000000',
    finalized: true,
  ),
  opponent: _entry(
    duelWalletB,
    commitId: 'bb' * 32,
    verified: true,
    forecast: {'temperature_c': 14.0},
    reward: '10000000',
    finalized: true,
  ),
  outcome: {
    'result': 'creator',
    'winner': duelWalletA,
    'reason': 'higher_chain_reward',
    'note':
        'The chain paid this forecast more: its oracle receipt scored higher.',
  },
);
