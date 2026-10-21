import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/crypto/transparent_transfer_authorization.dart';

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('mobile rebuilds the byte-identical base-unit authorization vector', () {
    final bytes = File(
      'contract-fixtures/transparent-transfer-auth-vector.json',
    ).readAsBytesSync();
    expect(
      sha256.convert(bytes).toString(),
      'ebbc584576df327dcc3cdf7433b563f59c60471db2266847d3eaefb29b341886',
    );
    final vector = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(vector['amount_unit'], 'integer base units');
    final fixture = vector['case'] as Map<String, dynamic>;
    final message = transparentTransferAuthorizationMessage(
      chainId: fixture['chain_id'] as String,
      networkId: fixture['network_id'] as String,
      from: fixture['from'] as String,
      to: fixture['to'] as String,
      amountBaseUnits: fixture['amount'] as int,
      nonce: fixture['nonce'] as int,
    );
    expect(_hex(message), fixture['preimage_hex']);
  });
}
