import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/send_allowlist.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

const _key = WalletSecureStorage.sendAllowlistKey;
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = WalletSecureStorage();

  // First, on the real channel: setMockInitialValues below replaces it.
  test('a secure-storage read error fails closed', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _channel,
      (_) async => throw PlatformException(code: 'read_failed'),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    expect(
      await storage.getSendAllowlist(),
      SendAllowlistSettings.unreadableOn,
    );
  });

  test('nothing saved is off', () async {
    FlutterSecureStorage.setMockInitialValues({});
    expect(await storage.getSendAllowlist(), SendAllowlistSettings.off);
  });

  for (final corrupt in const [
    '',
    'not json',
    '{"enabled":tr',
    '[]',
    'true',
    'null',
    '{}',
    '{"enabled":"true"}',
    '{"enabled":false,"turns_off_at":"soon"}',
    '{"enabled":true,"turns_off_at":99999999999999999}',
  ]) {
    test('saved "$corrupt" fails closed', () async {
      FlutterSecureStorage.setMockInitialValues({_key: corrupt});
      final settings = await storage.getSendAllowlist();
      expect(settings, SendAllowlistSettings.unreadableOn);
      expect(SendAllowlistPolicy().isOn(settings), isTrue);
    });
  }

  test('saved settings read back as saved', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final pending = SendAllowlistSettings(
      enabled: true,
      turnsOffAt: DateTime.utc(2026, 11, 3),
    );
    for (final saved in [
      SendAllowlistSettings.off,
      const SendAllowlistSettings(enabled: true),
      pending,
    ]) {
      await storage.saveSendAllowlist(saved);
      expect(await storage.getSendAllowlist(), saved);
    }
  });

  test('the turn-off path replaces a corrupt value with a real one', () async {
    FlutterSecureStorage.setMockInitialValues({_key: 'not json'});
    final now = DateTime.utc(2026, 11, 2, 12);
    final policy = SendAllowlistPolicy(clock: () => now);

    await storage.saveSendAllowlist(
      policy.requestTurnOff(await storage.getSendAllowlist()),
    );

    final saved = await storage.getSendAllowlist();
    expect(saved.unreadable, isFalse);
    expect(saved.turnsOffAt, now.add(const Duration(hours: 24)));
  });

  test('Emergency Wipe clears a corrupt value', () async {
    FlutterSecureStorage.setMockInitialValues({_key: 'not json'});
    await storage.clearWalletData();
    expect(await storage.getSendAllowlist(), SendAllowlistSettings.off);
  });
}
