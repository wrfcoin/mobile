import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/notifications/fcm_token_service.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _StaticPlatform implements FcmPlatform {
  _StaticPlatform(this._token);

  final String _token;

  @override
  Future<String?> getToken() async => _token;

  @override
  Stream<String?> get onTokenRefresh => const Stream.empty();
}

class _RotatingPlatform implements FcmPlatform {
  final StreamController<String?> _controller =
      StreamController<String?>.broadcast();

  @override
  Future<String?> getToken() async => 'initial-token';

  @override
  Stream<String?> get onTokenRefresh => _controller.stream;

  void rotate(String newToken) => _controller.add(newToken);

  Future<void> close() => _controller.close();
}

/// Dio interceptor that counts POST calls and can be configured to fail.
class _CountingInterceptor extends Interceptor {
  int callCount = 0;
  bool shouldFail;

  _CountingInterceptor({this.shouldFail = false});

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    callCount++;
    if (shouldFail) {
      handler.reject(
        DioException(requestOptions: options, message: 'network error'),
        true,
      );
    } else {
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{'ok': true},
        ),
        true,
      );
    }
  }
}

ApiClient _makeClient(_CountingInterceptor interceptor) {
  final dio = Dio();
  dio.interceptors.add(interceptor);
  return ApiClient(dio: dio);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('FcmTokenService — platform null', () {
    test('initialize is a no-op when platform is null', () async {
      final service = FcmTokenService(apiClient: ApiClient(dio: Dio()));
      await expectLater(service.initialize(), completes);
    });

    test('clearToken does not throw when nothing is stored', () async {
      final service = FcmTokenService(apiClient: ApiClient(dio: Dio()));
      await expectLater(service.clearToken(), completes);
    });

    test('getStoredToken returns null before any initialization', () async {
      final service = FcmTokenService(apiClient: ApiClient(dio: Dio()));
      expect(await service.getStoredToken(), isNull);
    });
  });

  group('FcmTokenService — registration', () {
    test('stores token and calls backend on first initialization', () async {
      final interceptor = _CountingInterceptor();
      final service = FcmTokenService(
        apiClient: _makeClient(interceptor),
        platform: _StaticPlatform('token-abc'),
      );

      await service.initialize();

      expect(await service.getStoredToken(), 'token-abc');
      expect(interceptor.callCount, 1);
    });

    test('does not re-register when token is unchanged and not stale', () async {
      final interceptor = _CountingInterceptor();
      final service = FcmTokenService(
        apiClient: _makeClient(interceptor),
        platform: _StaticPlatform('token-abc'),
      );

      // First init: registers
      await service.initialize();
      final firstCount = interceptor.callCount;

      // Second init: same token, freshly registered — should not call backend
      await service.initialize();

      expect(interceptor.callCount, firstCount);
    });

    test('re-registers on token rotation', () async {
      final interceptor = _CountingInterceptor();
      final platform = _RotatingPlatform();
      final service = FcmTokenService(
        apiClient: _makeClient(interceptor),
        platform: platform,
      );

      await service.initialize();
      final afterInit = interceptor.callCount;

      platform.rotate('rotated-token-xyz');
      // Allow the async listener to fire
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(interceptor.callCount, greaterThan(afterInit));
      expect(await service.getStoredToken(), 'rotated-token-xyz');

      await platform.close();
    });
  });

  group('FcmTokenService — retry with backoff', () {
    test('retries up to _maxRetries times on failure then gives up', () async {
      final interceptor = _CountingInterceptor(shouldFail: true);
      final service = FcmTokenService(
        apiClient: _makeClient(interceptor),
        platform: _StaticPlatform('token-retry'),
        retryBaseDelay: Duration.zero, // zero delay for fast tests
      );

      await service.initialize(); // must not throw

      // 3 attempts (maxRetries = 3)
      expect(interceptor.callCount, 3);
    });

    test('succeeds on second attempt after initial failure', () async {
      int calls = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            if (calls < 2) {
              handler.reject(
                DioException(requestOptions: options, message: 'transient'),
                true,
              );
            } else {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{'ok': true},
                ),
                true,
              );
            }
          },
        ),
      );

      final service = FcmTokenService(
        apiClient: ApiClient(dio: dio),
        platform: _StaticPlatform('token-retry-ok'),
        retryBaseDelay: Duration.zero,
      );

      await service.initialize();

      expect(calls, 2);
      // Registration timestamp should be set (successful second attempt)
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('fcm_token_registered_at_ms'), isNotNull);
    });
  });

  group('FcmTokenService — clearToken', () {
    test('removes stored token and timestamp', () async {
      final service = FcmTokenService(
        apiClient: _makeClient(_CountingInterceptor()),
        platform: _StaticPlatform('token-to-clear'),
      );

      await service.initialize();
      expect(await service.getStoredToken(), isNotNull);

      await service.clearToken();

      expect(await service.getStoredToken(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('fcm_token_registered_at_ms'), isNull);
    });
  });
}
