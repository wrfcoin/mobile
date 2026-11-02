/// Test fixture following the live route's shape on 2026-11-02. The keys and
/// amounts are made up for tests and are not chain data.
final loadedNodes = <String, dynamic>{
  'chain': {
    'networkId': 'testnet',
    'chainId': '888',
    'height': 11601,
    'status': 'ok',
  },
  'producers': {
    'status': 'ok',
    'rosterSource': 'test roster',
    'window': {
      'fromHeight': 11538,
      'toHeight': 11601,
      'read': 63,
      'unreadable': 1,
      'unsigned': 0,
    },
    'members': [
      {
        'producerId': 'producer-a',
        'publicKey': 'a1' * 32,
        'payoutAddress': '0x${'11' * 20}',
        'blocksInWindow': 63,
        'lastBlock': {'height': 11601, 'time': '2026-11-02T01:44:38.000Z'},
        'earnedTotal': null,
      },
      {
        'producerId': 'producer-b',
        'publicKey': 'b2' * 32,
        'payoutAddress': '0x${'22' * 20}',
        'blocksInWindow': 0,
        'lastBlock': null,
        'earnedTotal': '150000000',
      },
    ],
    'unrostered': [
      {
        'publicKey': 'c3' * 32,
        'blocksInWindow': 1,
        'lastBlock': {'height': 11540, 'time': null},
      },
    ],
  },
  'bonded': {
    'status': 'ok',
    'epoch': 22,
    'discovery': {
      'settlementEpochs': [22, 21],
      'configured': 1,
    },
    'nodes': [
      {
        'deploymentId': 'd4' * 32,
        'alias': 'node-one',
        'principal': '25000000000',
        'escrowBalance': '25000000000',
        'jailed': false,
        'registeredEpoch': 0,
        'exitEffectiveHeight': null,
        'payoutAddress': '0x${'33' * 20}',
        'earnedTotal': '75851851776',
        'lastPayout': {
          'epoch': 21,
          'status': 'PROVISIONAL',
          'amount': '18962962944',
        },
      },
      {
        'deploymentId': 'e5' * 32,
        'alias': null,
        'principal': null,
        'escrowBalance': null,
        'jailed': true,
        'registeredEpoch': null,
        'exitEffectiveHeight': null,
        'payoutAddress': null,
        'earnedTotal': null,
        'lastPayout': null,
      },
    ],
  },
  'attesters': {
    'status': 'ok',
    'quorum': 2,
    'ids': ['f6' * 32, 'f7' * 32],
  },
  'checkedAt': '2026-11-02T01:45:00.000Z',
};

/// Sections the node could not answer, and an empty bond list.
const partlyUnavailableNodes = <String, dynamic>{
  'chain': {
    'networkId': null,
    'chainId': null,
    'height': null,
    'status': 'unavailable',
  },
  'producers': {
    'status': 'unavailable',
    'rosterSource': 'test roster',
    'window': null,
    'members': <Object>[],
    'unrostered': <Object>[],
  },
  'bonded': {
    'status': 'ok',
    'epoch': 22,
    'discovery': {'settlementEpochs': <Object>[], 'configured': 0},
    'nodes': <Object>[],
  },
  'attesters': {'status': 'unavailable', 'quorum': null, 'ids': <Object>[]},
  'checkedAt': '2026-11-02T01:45:00.000Z',
};
