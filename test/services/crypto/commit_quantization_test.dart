import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/crypto/commit_id.dart';

void main() {
  final vectors = jsonDecode(
    File('test/fixtures/serde-float-golden/vectors.json').readAsStringSync(),
  ) as List;
  final expected = jsonDecode(
    File('test/fixtures/serde-float-golden/commit-ids.json').readAsStringSync(),
  ) as List;
  // vectors.json is copied byte-for-byte from backend#1343 (3ddaefe7).
  // commit-ids.json was independently generated with node:crypto SHA3-256,
  // JS JSON.stringify, and the owner-ruled IEEE half-away-from-zero expression.
  for (var i = 0; i < vectors.length; i++) {
    final vector = vectors[i] as Map;
    final golden = expected[i] as Map;
    test(
      'backend vector ${vector['raw']} has identical JSON text and commit id',
      () {
        expect(golden['raw'], vector['raw']);
        expect(golden['printed'], vector['quantized']);
        final pressure = double.parse(vector['raw'] as String);
        expect(collectCanonicalPayload(pressure), golden['payload']);
        expect(
          computeCollectCommitId(
            pressureHpa: pressure,
            nonce: 'n',
            stationId: 's',
            timestampSeconds: 1790000000,
          ),
          golden['commitId'],
        );
      },
    );
  }
}
