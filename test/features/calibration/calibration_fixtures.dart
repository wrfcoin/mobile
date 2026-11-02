/// The shape backend `stationCalibrationView` answers. The "none" answer is
/// the one https://wrfcoin.com returned for an uncertified alias.
const _roots = [
  {
    'rootId': 'wrfcoin-owner-testnet',
    'subject': 'WRFCoin owner (testnet)',
    'publicKeyHex': '1b4a',
    'fingerprintSha256': 'd5d3',
  },
];

Map<String, dynamic> noneJson() => {
  'success': true,
  'stationAlias': 'st_7d29a4c1e0b8',
  'status': 'none',
  'certificate': null,
  'history': <Object>[],
  'trustRoots': _roots,
  'checkedAt': '2026-11-02T01:45:23.954Z',
};

Map<String, dynamic> certificateJson({String status = 'calibrated'}) => {
  'cid': 'bafy-certificate-id',
  'artifactId': 'artifact-1',
  'status': status,
  'reasonCodes': <String>[],
  'issuer': {
    'issuerId': 'wrfcoin-owner-testnet',
    'trustRootId': 'wrfcoin-owner-testnet',
  },
  'issuedAt': '2026-10-01T00:00:00.000Z',
  'expiresAt': '2027-10-01T00:00:00.000Z',
  'ownerAddress': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'calibration': {
    'sensor': 'Davis 6152',
    'method': 'Side-by-side against a reference',
    'reference': 'NIST-traceable thermometer',
    'notes': '',
  },
  'revocation': null,
  'artifact': {'schema': 'calibration-certificate-v1', 'signature': 'ab12'},
};

Map<String, dynamic> calibratedJson() => {
  ...noneJson(),
  'status': 'calibrated',
  'certificate': certificateJson(),
};

Map<String, dynamic> revokedJson() => {
  ...noneJson(),
  'status': 'revoked',
  'certificate': {
    ...certificateJson(status: 'revoked'),
    'revocation': {
      'reason': 'sensor_moved',
      'revokedAt': '2026-10-20T00:00:00.000Z',
    },
  },
};
