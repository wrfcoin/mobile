import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';

/// Secret key of core4's golden case `transparent_transfer_authorization_v2`
/// (shared-protocol/tests/fixtures/golden/signing_preimage_v2.json, case 10,
/// `signer_secret_hex`). Public test data; it controls no real account.
const _vectorSecretHex =
    '73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883';

Map<String, dynamic> _vectorCase() {
  final vector = jsonDecode(
    File('contract-fixtures/transparent-transfer-auth-vector.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  return vector['case'] as Map<String, dynamic>;
}

void main() {
  test('signed /wallet/send body reproduces core4 canonical vector', () async {
    final fixture = _vectorCase();
    final signer = await Ed25519TransferSigner.fromSeedHex(_vectorSecretHex);

    final body = await buildSignedTransferBody(
      signer: signer,
      domain: TransferSigningDomain(
        chainId: fixture['chain_id'] as String,
        networkId: fixture['network_id'] as String,
      ),
      from: fixture['from'] as String,
      to: fixture['to'] as String,
      amountBaseUnits: '${fixture['amount']}',
      nonce: '${fixture['nonce']}',
    );

    expect(body, <String, String>{
      'from': 'wrf_faucet_gv',
      'to': 'wrf_recipient_gv',
      'amount': '1000',
      'nonce': '5',
      'auth_pubkey': fixture['signer_public_key_hex'] as String,
      'auth_signature': fixture['signature_hex'] as String,
    });
  });

  test('rejects display-unit and non-integer amounts before signing', () async {
    final signer = await Ed25519TransferSigner.fromSeedHex(_vectorSecretHex);
    for (final amount in ['0', '1.5', '-1', '', '01', '9007199254740992']) {
      await expectLater(
        buildSignedTransferBody(
          signer: signer,
          domain: TransferSigningDomain.configured,
          from: '0x${'1' * 40}',
          to: '0x${'2' * 40}',
          amountBaseUnits: amount,
          nonce: '0',
        ),
        throwsArgumentError,
        reason: amount,
      );
    }
  });

  test('debug signing domain defaults to chain 888 / testnet', () {
    expect(TransferSigningDomain.configured.chainId, '888');
    expect(TransferSigningDomain.configured.networkId, 'testnet');
  });
}
