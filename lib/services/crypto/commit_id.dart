import 'dart:convert';

import 'package:pointycastle/digests/sha3.dart';

// Local re-computation of the commit id core4 verifies, so the phone never
// signs a commit id it did not derive itself (design §4 "Built locally").
//
// Backend shared/commit-reveal-hash.ts `computeCommitId`:
//   SHA3-256( canonicalJson(data) || nonce || station_id || timestamp ||
//             contribution_type ) with the literals joined by "||".
// For a Collect body the canonical reading is the sorted five-field object
// `buildCanonicalReading` builds (only pressure is non-zero).

const _contributionType = 'contribution';

/// JS `Number.prototype.toString` for the finite doubles a pressure can be:
/// integral values print without a fraction (1013, not 1013.0).
String jsNumberString(double value) {
  if (!value.isFinite) {
    throw ArgumentError('value must be finite: $value');
  }
  if (value == 0) return '0';
  if (value == value.truncateToDouble() && value.abs() < 1e21) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// The backend's exact IEEE 2dp rule: half away from zero, -0 normalized.
/// The product is a double first (1.005 consequently rounds to 1).
double quantizeWeatherMeasurement(double value) {
  if (!value.isFinite) throw ArgumentError('measurement must be finite');
  final q = (value.sign * (value.abs() * 100).round()) / 100;
  return q == 0 ? 0.0 : q;
}

/// The exact JSON text the backend hashes for a pressure-only Collect reading
/// (keys in serde_json/BTreeMap order).
String collectCanonicalPayload(double pressureHpa) =>
    '{"humidity_pct":0,"pressure_hpa":${jsNumberString(quantizeWeatherMeasurement(pressureHpa))},'
    '"rainfall_mm":0,"temperature_c":0,"wind_mps":0}';

String computeCollectCommitId({
  required double pressureHpa,
  required String nonce,
  required String stationId,
  required int timestampSeconds,
}) {
  final preimage =
      '${collectCanonicalPayload(pressureHpa)}||$nonce||$stationId'
      '||$timestampSeconds||$_contributionType';
  final digest = SHA3Digest(256).process(utf8.encode(preimage));
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
