import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/governance_vote_signing.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../test_helpers/fakes.dart';

// The website/core4 vector wallet (seed 0x42 x 32), synthetic.
const seed = '4242424242424242424242424242424242424242424242424242424242424242';
const address = '0xa307fb31c7585b6ccb5dc3ddc844e22b14b7aa0d';

void main() {
  late FakeLocalAuthClient auth;
  late KeyManager keys;

  setUp(() async {
    LoginAttemptGuard.resetIsolateStateForTest();
    auth = FakeLocalAuthClient(authenticateResult: true);
    keys = KeyManager(
      biometric: BiometricService(client: auth),
      storage: InMemoryKeyValueStorage(),
    );
    await keys.storeKeys(
      mnemonic: 'never read by a vote',
      privateKey: seed,
      address: address,
      keyScheme: KeyManager.canonicalKeyScheme,
    );
  });

  test('inactive right after the unlock, then resumed: signs', () async {
    var after = 0;
    final signer = GovernanceVoteSigner(
      keyManager: keys,
      isForeground: () =>
          auth.authenticateBiometricOnlyCalls.isEmpty || ++after > 3,
    );
    final signed = await signer.signVote('proposal-1', true);
    expect(signed, isNotNull);
    expect(signed!['signature'], hasLength(128));
    expect(auth.authenticateBiometricOnlyCalls, hasLength(1));
  });

  test('stays paused after the unlock: refuses, says nothing was sent', () {
    final signer = GovernanceVoteSigner(
      keyManager: keys,
      isForeground: () => auth.authenticateBiometricOnlyCalls.isEmpty,
      resumeTimeout: const Duration(milliseconds: 300),
    );
    expect(
      signer.signVote('proposal-1', true),
      throwsA(
        isA<GovernanceSigningUnavailable>().having(
          (e) => e.toString(),
          'message',
          contains('Nothing was sent.'),
        ),
      ),
    );
  });
}
