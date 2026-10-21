import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../../test_helpers/fakes.dart';

const ownerSeedA =
    '0707070707070707070707070707070707070707070707070707070707070707';
const ownerSeedB =
    '0808080808080808080808080808080808080808080808080808080808080808';
const ownerDomain = TransferSigningDomain(chainId: 'c-1', networkId: 'n-1');

/// Backend ownership read (backend#1459): flat camelCase. The registered
/// owner is shown SHORT to anonymous viewers, so callers must match on
/// `ownerCommitment`, never on `owner`. Test-call conveniences: `frozen` takes
/// `{'since_height': n}` and `pending` the snake_case node map; both are
/// converted to the backend shape here.
Map<String, dynamic> ledgerJson({
  String stationId = 'st',
  String owner = '0xe5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5',
  int nonce = 3,
  Object? frozen,
  bool deactivated = false,
  Object? pending,
  bool consent = true,
  bool actions = true,
  int observed = 1000,
  int settled = 990,
}) {
  String commit(String id, String a) {
    try {
      return ownerCommitment(id, a);
    } on ArgumentError {
      return 'f' * 64; // a test address that is not a real 20-byte address
    }
  }

  String short(String a) =>
      a.length <= 12 ? a : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';
  final p = pending as Map<String, dynamic>?;
  return {
    'success': true,
    'stationAlias': stationAliasOf(stationId),
    'isOwner': false,
    'owner': short(owner),
    'ownerCommitment': ownerCommitment(stationId, owner),
    'ownerNonce': nonce,
    'frozen': frozen == null
        ? null
        : {'sinceHeight': (frozen as Map)['since_height']},
    'ownerDeactivated': deactivated,
    'rewardsSuspended': false,
    'pendingRecovery': p == null
        ? null
        : {
            'fromOwner': short(p['from_owner_address'] as String),
            'toOwner': short(p['to_owner_address'] as String),
            'fromOwnerCommitment': commit(
              stationId,
              p['from_owner_address'] as String,
            ),
            'toOwnerCommitment': commit(
              stationId,
              p['to_owner_address'] as String,
            ),
            'recoveryNonce': p['recovery_nonce'],
            'filedAtHeight': p['filed_at_height'],
            'executableAtHeight': p['executable_at_height'],
            'noticeBlocks': 34000,
          },
    'governanceActive': true,
    'features': {
      'stationOwnerConsent': consent,
      'stationOwnerActions': actions,
      'stationActiveRewardGate': false,
    },
    'observedAtHeight': observed,
    'settledHeight': settled,
  };
}

class OwnerWallet {
  OwnerWallet(this.session, this.address, this.pubkey);
  final StationSigningSession session;
  final String address;
  final String pubkey;
}

Future<OwnerWallet> ownerWallet(String seed) async {
  final signer = await Ed25519TransferSigner.fromSeedHex(seed);
  final address = chainAddressFromEd25519PublicKey(signer.publicKey);
  final km = KeyManager(
    biometric: BiometricService(client: FakeLocalAuthClient()),
    storage: InMemoryKeyValueStorage(),
  );
  await km.storeKeys(mnemonic: 'x y', privateKey: seed, address: address);
  final session = (await StationSigningService(
    keyManager: km,
    domain: ownerDomain,
    isForeground: () => true,
  ).openSession())!;
  return OwnerWallet(session, address, session.publicKeyHex);
}

class FakeOwnerApi implements StationOwnerApi {
  FakeOwnerApi(this.ledgerBody);
  Map<String, dynamic> ledgerBody;
  final List<SignedOwnerPayload> submitted = [];
  StationOwnerException? submitError;
  StationOwnerException? readError;

  @override
  Future<OwnerLedger> readLedger(String stationId) async {
    if (readError != null) throw readError!;
    return OwnerLedger.fromJson(ledgerBody);
  }

  @override
  Future<OwnerSubmitReceipt> submit(SignedOwnerPayload tx) async {
    if (submitError != null) throw submitError!;
    submitted.add(tx);
    return const OwnerSubmitReceipt(
      transactionIds: ['aa'],
      admissionHeight: 1001,
    );
  }
}

Future<bool> verifyEd25519(String pub, String sig, List<int> msg) {
  List<int> unhex(String s) => [
    for (var i = 0; i < s.length; i += 2)
      int.parse(s.substring(i, i + 2), radix: 16),
  ];
  return Ed25519().verify(
    msg,
    signature: Signature(
      unhex(sig),
      publicKey: SimplePublicKey(unhex(pub), type: KeyPairType.ed25519),
    ),
  );
}

/// Counts pushed and popped routes: a double tap must push ONE dialog and pop
/// it once.
class PopCounter extends NavigatorObserver {
  int pops = 0;
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}

/// Calls a button's handler twice back to back, with no frame in between:
/// exactly what a fast double tap delivers before the UI can rebuild. (A real
/// tap is also protected by the Navigator and by disabled buttons; calling the
/// handler directly proves the handler's OWN guard.)
void invokeTwice(WidgetTester t, Finder button) {
  final onPressed = t.widget<ButtonStyleButton>(button).onPressed;
  expect(onPressed, isNotNull, reason: 'the button must be enabled');
  onPressed!();
  onPressed();
}
