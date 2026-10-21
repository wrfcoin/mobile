import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final screenSecurityClientProvider = Provider<ScreenSecurityClient>((ref) {
  return PlatformScreenSecurityClient();
});

final screenSecurityServiceProvider = Provider<ScreenSecurityService>((ref) {
  return ScreenSecurityService(client: ref.read(screenSecurityClientProvider));
});

abstract class ScreenSecurityClient {
  Future<void> enableProtection();
  Future<void> disableProtection();
}

class PlatformScreenSecurityClient implements ScreenSecurityClient {
  static const _channel = MethodChannel(
    'com.wrfcoin.wrfcoin_mobile/screen_security',
  );

  @override
  Future<void> enableProtection() async {
    await _channel.invokeMethod<void>('enableScreenSecurity');
  }

  @override
  Future<void> disableProtection() async {
    await _channel.invokeMethod<void>('disableScreenSecurity');
  }
}

class ScreenSecurityService {
  final ScreenSecurityClient _client;

  ScreenSecurityService({required this._client});

  Future<void> enableProtection() async {
    if (kIsWeb) return;
    try {
      await _client.enableProtection();
    } catch (_) {
      // Silently fail — screen security is best-effort.
    }
  }

  Future<void> disableProtection() async {
    if (kIsWeb) return;
    try {
      await _client.disableProtection();
    } catch (_) {
      // Silently fail — screen security is best-effort.
    }
  }
}
