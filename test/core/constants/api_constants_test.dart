import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';

void main() {
  group('ApiConstants.baseUrl', () {
    test('has no implicit release endpoint', () {
      expect(ApiConstants.baseUrl, isEmpty);
      expect(ApiConstants.effectiveBaseUrl, ApiConstants.debugDefaultBaseUrl);
    });
  });

  group('ApiConstants.isLocalUrl', () {
    test('detects localhost', () {
      expect(ApiConstants.isLocalUrl('http://localhost:4001/api'), isTrue);
    });

    test('detects 127.0.0.1', () {
      expect(ApiConstants.isLocalUrl('http://127.0.0.1:4001/api'), isTrue);
    });

    test('detects IPv6 loopback', () {
      expect(ApiConstants.isLocalUrl('http://[::1]:4001/api'), isTrue);
    });

    test('detects 0.0.0.0', () {
      expect(ApiConstants.isLocalUrl('http://0.0.0.0:4001/api'), isTrue);
    });

    test('detects .local suffix', () {
      expect(ApiConstants.isLocalUrl('http://myhost.local:4001/api'), isTrue);
    });

    test('rejects production URL', () {
      expect(ApiConstants.isLocalUrl('https://api.wrfcoin.io/api'), isFalse);
    });

    test('rejects staging URL', () {
      expect(
        ApiConstants.isLocalUrl('https://staging-api.wrfcoin.io/api'),
        isFalse,
      );
    });

    test('handles malformed URL gracefully', () {
      expect(ApiConstants.isLocalUrl('not a url'), isFalse);
    });

    test('handles empty string', () {
      expect(ApiConstants.isLocalUrl(''), isFalse);
    });
  });

  group('ApiConstants referral routes', () {
    test('exposes referral endpoints for mobile onboarding', () {
      expect(ApiConstants.referralGenerate, '/referrals/generate');
      expect(ApiConstants.referralActivate, '/referrals/activate');
      expect(ApiConstants.referralStats('wrf1abc'), '/referrals/stats/wrf1abc');
    });
  });
}
