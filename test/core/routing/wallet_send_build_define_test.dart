import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/feature_flags/build_flags.dart';

// The offline test matrix supplies expected values independently of the
// production resolver. dart.vm.profile selects foundation's profile constant;
// this checks compiled selection without building an APK.
const _expectedProfile = bool.fromEnvironment('WRFCOIN_TEST_EXPECT_PROFILE');
const _expectedSend = bool.fromEnvironment(
  'WRFCOIN_TEST_EXPECT_SEND',
  defaultValue: true,
);

void main() {
  test('compiled build: profile=$_expectedProfile, Send=$_expectedSend', () {
    expect(kProfileMode, _expectedProfile);
    expect(WalletSendGate.enabled, _expectedSend);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(walletSendEnabledProvider), _expectedSend);
  });
}
