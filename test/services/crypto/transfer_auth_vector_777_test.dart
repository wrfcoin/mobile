import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/transparent_transfer_authorization.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

/// core4#3260: the live testnet transfer authorization vector. core4
/// (`tools/cli/WrfcoinCLI/src/crypto.rs`) produces these bytes and verifies the
/// signature with `authorize_debit`; frontend vendors the same file.
void main() {
  final bytes = File(
    'contract-fixtures/transparent-transfer-auth-vector-777.json',
  ).readAsBytesSync();
  final vector = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final fixture = vector['case'] as Map<String, dynamic>;
  final signer = vector['signer'] as Map<String, dynamic>;

  test('vendored vector is byte-identical to core4', () {
    expect(
      sha256.convert(bytes).toString(),
      '9a37d7f71d316aaf863ec1612e4fe3a7cb43cf0f9b300717565958b4a08a20c8',
    );
    expect(vector['domain_tag'], 'wrfcoin_transparent_transfer_auth_v2');
    expect(vector['amount_unit'], 'integer base units (1 WRF = 100000000)');
  });

  test('the shipped signing domain is the vector chain 777 / testnet', () {
    expect(fixture['chain_id'], '777');
    expect(fixture['network_id'], 'testnet');
    expect(TransferSigningDomain.configured.chainId, fixture['chain_id']);
    expect(TransferSigningDomain.configured.networkId, fixture['network_id']);
  });

  test('mobile rebuilds the preimage and reproduces the signature', () async {
    final credentials = await WalletSetupService().importFromMnemonic(
      signer['mnemonic'] as String,
    );
    expect(credentials.address, fixture['from']);

    final message = transparentTransferAuthorizationMessage(
      chainId: fixture['chain_id'] as String,
      networkId: fixture['network_id'] as String,
      from: fixture['from'] as String,
      to: fixture['to'] as String,
      amountBaseUnits: fixture['amount'] as int,
      nonce: fixture['nonce'] as int,
    );
    expect(_hex(message), fixture['preimage_hex']);

    final body = await buildSignedTransferBody(
      signer: await Ed25519TransferSigner.fromSeedHex(credentials.privateKey),
      domain: TransferSigningDomain.configured,
      from: credentials.address,
      to: fixture['to'] as String,
      amountBaseUnits: '${fixture['amount']}',
      nonce: '${fixture['nonce']}',
    );
    expect(body['amount'], '${fixture['amount']}');
    expect(body['auth_pubkey'], signer['ed25519_public_key_hex']);
    expect(body['auth_signature'], fixture['signature_hex']);
  });
}
