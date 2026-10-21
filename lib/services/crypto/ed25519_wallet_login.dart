import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/constants/api_constants.dart';
import 'signed_transfer.dart';
import 'wallet_setup_service.dart';

/// Domain tag on the first line of the backend's ed25519 login challenge
/// (backend#1208 `ED25519_WALLET_LOGIN_DOMAIN`).
const ed25519WalletLoginDomain = 'wrfcoin_wallet_login_ed25519_v1';

/// What the wallet expects the backend's ed25519 login challenge to name.
///
/// The challenge is checked against this BEFORE the wallet key signs it
/// (backend#1208 review, finding 2): a malicious or compromised backend must
/// not be able to get the wallet key to sign anything else, such as a
/// transfer authorization preimage.
class Ed25519LoginExpectation {
  const Ed25519LoginExpectation({
    required this.origin,
    required this.chainId,
    required this.network,
  });

  /// Relying-party origin (backend `WRFCOIN_WALLET_AUTH_ORIGIN`), e.g.
  /// `https://testnet.example`: scheme, host and optional port, no path.
  final String origin;
  final String chainId;
  final String network;

  /// Build-time configuration. The origin is `--dart-define`
  /// `WRFCOIN_WALLET_AUTH_ORIGIN`, or else the origin of the API base URL
  /// (the testnet edge serves the frontend and `/api` on the one public
  /// origin the backend signs into its challenge). Chain and network are the
  /// same `WRFCOIN_CHAIN_ID` / `WRFCOIN_NETWORK_ID` (explicit release chain / testnet) that
  /// transfers are signed for.
  static Ed25519LoginExpectation configured() {
    const explicitOrigin = String.fromEnvironment('WRFCOIN_WALLET_AUTH_ORIGIN');
    return Ed25519LoginExpectation(
      origin: explicitOrigin.isNotEmpty
          ? explicitOrigin
          : originOf(ApiConstants.effectiveBaseUrl) ?? '',
      chainId: TransferSigningDomain.configured.chainId,
      network: TransferSigningDomain.configured.networkId,
    );
  }

  /// `scheme://host[:port]` of [url], or null when it has none.
  static String? originOf(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri.origin;
  }
}

final RegExp _chainAddress = RegExp(r'^0x[0-9a-f]{40}$');

/// Why [message] is not exactly the ed25519 login challenge the wallet
/// expects for [address] and [nonce], or null when it is.
///
/// The message must match backend#1208 `buildEd25519WalletLoginMessage`
/// line for line: the domain tag first, this wallet's lowercase chain
/// address, the expected origin/host, `Scheme: ed25519`, the expected chain
/// ID and network, and the nonce the server returned alongside it. Only the
/// two timestamps are server-chosen, and they must be ISO-8601 instants with
/// the expiry still in the future on this device's clock ([now], default
/// `DateTime.now().toUtc()`), so an expired or replayed challenge never
/// reaches the key (the server enforces expiry too).
String? ed25519LoginChallengeProblem({
  required String message,
  required String address,
  required String nonce,
  required Ed25519LoginExpectation expected,
  DateTime? now,
}) {
  if (!_chainAddress.hasMatch(address)) return 'address is not a chain address';
  final origin = Ed25519LoginExpectation.originOf(expected.origin);
  if (origin == null || origin != expected.origin) {
    return 'expected origin is not configured';
  }
  if (!message.startsWith('$ed25519WalletLoginDomain\n')) {
    return 'missing ed25519 login domain tag';
  }
  if (nonce.isEmpty || nonce.contains('\n')) return 'bad nonce';

  final lines = message.split('\n');
  if (lines.length != 14) return 'unexpected challenge shape';
  final host = Uri.parse(origin).authority;
  final fixed = <int, String>{
    0: ed25519WalletLoginDomain,
    1: '$host wants you to sign in with your WRFCoin ed25519 account:',
    2: address,
    3: '',
    4: 'Sign in to WRFCoin Testnet.',
    5: '',
    6: 'URI: $origin',
    7: 'Version: 1',
    8: 'Scheme: ed25519',
    9: 'Chain ID: ${expected.chainId}',
    10: 'Network: ${expected.network}',
    11: 'Nonce: $nonce',
  };
  for (final entry in fixed.entries) {
    if (lines[entry.key] != entry.value) {
      return 'challenge line ${entry.key + 1} is not what this wallet expects';
    }
  }
  final issuedAt = _instant(lines[12], 'Issued At: ');
  final expiresAt = _instant(lines[13], 'Expiration Time: ');
  if (issuedAt == null || expiresAt == null || !expiresAt.isAfter(issuedAt)) {
    return 'bad challenge timestamps';
  }
  if (!expiresAt.isAfter((now ?? DateTime.now()).toUtc())) {
    return 'challenge has expired';
  }
  return null;
}

DateTime? _instant(String line, String prefix) {
  if (!line.startsWith(prefix)) return null;
  final value = line.substring(prefix.length);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$')
      .hasMatch(value)) {
    return null;
  }
  return DateTime.tryParse(value);
}

/// Thrown when a login challenge fails validation; nothing was signed.
class Ed25519LoginChallengeRejected implements Exception {
  Ed25519LoginChallengeRejected(this.reason);
  final String reason;

  @override
  String toString() => 'Ed25519LoginChallengeRejected: $reason';
}

/// The `POST /auth/wallet-login` fields an ed25519 login proves.
class Ed25519WalletLoginProof {
  const Ed25519WalletLoginProof({
    required this.publicKeyHex,
    required this.signatureHex,
  });

  final String publicKeyHex;
  final String signatureHex;
}

/// The only place the wallet key signs a login challenge.
///
/// Deliberately not a generic "sign this message" helper: it validates
/// [message] with [ed25519LoginChallengeProblem] first and throws
/// [Ed25519LoginChallengeRejected] without signing when it fails, and it
/// refuses a [seedHex] that does not control [address].
Future<Ed25519WalletLoginProof> signEd25519WalletLogin({
  required String seedHex,
  required String address,
  required String nonce,
  required String message,
  required Ed25519LoginExpectation expected,
}) async {
  final problem = ed25519LoginChallengeProblem(
    message: message,
    address: address,
    nonce: nonce,
    expected: expected,
  );
  if (problem != null) throw Ed25519LoginChallengeRejected(problem);

  final seed = _seedBytes(seedHex);
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = Uint8List.fromList(
    (await keyPair.extractPublicKey()).bytes,
  );
  if (WalletSetupService().chainAddressFromEd25519(publicKey) != address) {
    throw Ed25519LoginChallengeRejected('key does not control $address');
  }
  final signature = await Ed25519().sign(
    utf8.encode(message),
    keyPair: keyPair,
  );
  return Ed25519WalletLoginProof(
    publicKeyHex: _hex(publicKey),
    signatureHex: _hex(signature.bytes),
  );
}

List<int> _seedBytes(String seedHex) {
  final clean = seedHex.trim().toLowerCase().replaceFirst('0x', '');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(clean)) {
    throw ArgumentError('ed25519 seed must be 32 bytes of hex');
  }
  return <int>[
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ];
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
