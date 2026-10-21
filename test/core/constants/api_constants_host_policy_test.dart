import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';

/// Host canonicalization for the release startup gate (mobile#306). Mirrors
/// the shell gate scripts/validate-release-api-host.sh (#304).
void main() {
  group('ApiConstants.canonicalHost', () {
    test('lowercases and strips exactly one trailing dot', () {
      expect(ApiConstants.canonicalHost('LOCALHOST.'), 'localhost');
      expect(ApiConstants.canonicalHost('Api.Example.NET'), 'api.example.net');
      expect(ApiConstants.canonicalHost('a.b..'), 'a.b.');
    });
  });

  group('ApiConstants.isLocalUrl canonical forms', () {
    const local = <String, String>{
      'trailing-dot localhost': 'https://localhost./api',
      'uppercase trailing-dot localhost': 'https://LOCALHOST./api',
      'percent-encoded localhost': 'https://local%68ost/api',
      'sub.localhost': 'https://api.localhost/api',
      'mdns .local with trailing dot': 'https://phone.local./api',
      '.invalid': 'https://round6-nonexistent.invalid/api',
      '.test': 'https://release-api.test/api',
      '.example': 'https://api.example/api',
      '.internal': 'https://api.corp.internal/api',
      '.home.arpa': 'https://router.home.arpa/api',
      'single-label name': 'https://intranet/api',
      'IPv4 dotted loopback': 'https://127.0.0.1/api',
      'IPv4 loopback, not .1': 'https://127.8.9.10/api',
      'IPv4 short 127.1': 'https://127.1/api',
      'IPv4 hex 0x7f.1': 'https://0x7f.1/api',
      'IPv4 hex single': 'https://0x7f000001/api',
      'IPv4 octal 0177.0.0.1': 'https://0177.0.0.1/api',
      'IPv4 decimal 2130706433': 'https://2130706433/api',
      'IPv4 loopback with trailing dot': 'https://127.0.0.1./api',
      'IPv4 unspecified': 'https://0.0.0.0/api',
      'IPv6 ::1': 'https://[::1]/api',
      'IPv6 expanded loopback': 'https://[0:0:0:0:0:0:0:1]:443/api',
      'IPv6 unspecified ::': 'https://[::]/api',
      'IPv4-mapped IPv6 loopback': 'https://[::ffff:127.0.0.1]/api',
      'IPv4-mapped IPv6 uppercase': 'https://[::FFFF:7f00:1]/api',
      'IPv4-mapped IPv6 unspecified': 'https://[::ffff:0.0.0.0]/api',
    };
    local.forEach((label, url) {
      test('local: $label', () {
        expect(ApiConstants.isLocalUrl(url), isTrue, reason: url);
        expect(
          ApiConstants.releaseUrlProblem(url),
          contains('local host'),
          reason: url,
        );
      });
    });

    const notLocal = <String, String>{
      'funnel host': 'https://wrfcoin-testnet.taila1c049.ts.net/api',
      'funnel host, trailing dot and case':
          'https://WRFCOIN-TESTNET.taila1c049.ts.net./api',
      'other ts.net host': 'https://other-node.example.ts.net/api',
      'public IPv4 literal': 'https://203.0.113.10/api',
      'public IPv6 literal': 'https://[2001:db8::1]/api',
      'mapped public IPv4': 'https://[::ffff:203.0.113.10]/api',
      'name containing localhost': 'https://localhost.example.net/api',
      'name ending in local word': 'https://notlocal.net/api',
    };
    notLocal.forEach((label, url) {
      test('not local: $label', () {
        expect(ApiConstants.isLocalUrl(url), isFalse, reason: url);
      });
    });
  });

  group('ApiConstants.releaseUrlProblem host policy', () {
    test('funnel and ts.net hosts pass', () {
      for (final url in [
        'https://wrfcoin-testnet.taila1c049.ts.net/api',
        'https://WRFCOIN-TESTNET.taila1c049.ts.net./api',
        'https://other-node.example.ts.net:8443/api',
      ]) {
        expect(ApiConstants.releaseUrlProblem(url), isNull, reason: url);
      }
    });

    test('public IP literals are refused (use a DNS name)', () {
      for (final url in [
        'https://203.0.113.10/api',
        'https://[2001:db8::1]/api',
        'https://[::ffff:203.0.113.10]/api',
        'https://10.1/api',
        'https://api.wrfcoin.123/api',
      ]) {
        expect(
          ApiConstants.releaseUrlProblem(url),
          contains('IP literal'),
          reason: url,
        );
      }
    });

    test('placeholder hosts are caught after canonicalization', () {
      expect(
        ApiConstants.releaseUrlProblem('https://API.WRFCOIN.APP./api'),
        contains('placeholder'),
      );
    });

    test('non-LDH hosts and userinfo are refused', () {
      expect(
        ApiConstants.releaseUrlProblem('https://a..b.net/api'),
        contains('invalid host'),
      );
      expect(
        ApiConstants.releaseUrlProblem('https://under_score.example.net/api'),
        contains('invalid host'),
      );
      expect(
        ApiConstants.releaseUrlProblem('https://user@api.wrfcoin-ci.net/api'),
        contains('userinfo'),
      );
    });

    test('the debug default stays local and release-invalid', () {
      expect(ApiConstants.isLocalUrl(ApiConstants.debugDefaultBaseUrl), isTrue);
      expect(
        ApiConstants.releaseUrlProblem(ApiConstants.debugDefaultBaseUrl),
        isNotNull,
      );
    });
  });
}
