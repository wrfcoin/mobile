import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/crypto/commit_id.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

// Golden vectors computed with the backend's own algorithm
// (wrfcoin/backend shared/commit-reveal-hash.ts `computeCommitId` over the
// canonical reading `buildCanonicalReading` produces for a Collect body:
// SHA3-256(canonicalJson || nonce || station || timestamp || 'contribution')).
const _nonce = '0123456789abcdef0123456789abcdef';
const _station = 'mob-0123456789abcdef0123456789abcdef';
const _ts = 1790683200;

void main() {
  test('collectContributionType is core4/backend "contribution"', () {
    // core4 native-chain launch_api routes/transactions.rs:678 hardcodes
    // contribution_type "contribution" (commit_authorization_v2 preimage);
    // backend server/routes/oracle-submit-routes.ts CONTRIBUTION_TYPE.
    expect(collectContributionType, 'contribution');
  });

  test('canonical payload is the sorted five-field reading', () {
    expect(
      collectCanonicalPayload(1013.25),
      '{"humidity_pct":0,"pressure_hpa":1013.25,"rainfall_mm":0,'
      '"temperature_c":0,"wind_mps":0}',
    );
  });

  test('commit id matches the backend for a fractional pressure', () {
    expect(
      computeCollectCommitId(
        pressureHpa: 1013.25,
        nonce: _nonce,
        stationId: _station,
        timestampSeconds: _ts,
      ),
      '2d27848d5c0f5d706bc597dc8c9fc397b7ff658400161d3229d194025863f261',
    );
  });

  test('a whole-number pressure serializes like JS (1013, not 1013.0)', () {
    expect(jsNumberString(1013.0), '1013');
    expect(
      computeCollectCommitId(
        pressureHpa: 1013.0,
        nonce: _nonce,
        stationId: _station,
        timestampSeconds: _ts,
      ),
      'c7584361c4cf9913fd2a8cd05f48301112e024b2918c053b545d862e8fe1414c',
    );
    expect(
      computeCollectCommitId(
        pressureHpa: 0.5,
        nonce: 'n',
        stationId: 's',
        timestampSeconds: 1,
      ),
      'e8442c488a982ebd671ea5283b4fca88d8395c7319ce05b299fe8a2b209cf714',
    );
  });

  test('jsNumberString covers negatives, zero and non-finite', () {
    expect(jsNumberString(0.0), '0');
    expect(jsNumberString(-0.0), '0');
    expect(jsNumberString(-4.5), '-4.5');
    expect(() => jsNumberString(double.nan), throwsArgumentError);
    expect(() => jsNumberString(double.infinity), throwsArgumentError);
  });
}
