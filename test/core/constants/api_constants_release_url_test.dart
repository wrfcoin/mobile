import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';

void main() {
  group('ApiConstants.releaseUrlProblem', () {
    test('rejects unset and malformed URLs', () {
      expect(ApiConstants.releaseUrlProblem(''), isNotNull);
      expect(ApiConstants.releaseUrlProblem('not a url'), isNotNull);
    });

    test('rejects non-HTTPS and local URLs', () {
      expect(
        ApiConstants.releaseUrlProblem('http://release-api.test/api'),
        contains('https'),
      );
      expect(
        ApiConstants.releaseUrlProblem('https://localhost/api'),
        contains('local'),
      );
    });

    test('rejects every known placeholder host', () {
      for (final host in ApiConstants.placeholderHosts) {
        expect(
          ApiConstants.releaseUrlProblem('https://$host/api'),
          contains('placeholder'),
          reason: host,
        );
      }
    });

    test('accepts a syntactically valid non-placeholder HTTPS URL', () {
      expect(
        ApiConstants.releaseUrlProblem(
          'https://release-api.wrfcoin-ci-fixture.net/api',
        ),
        isNull,
      );
    });

    test('debug fallback is local and never a valid release URL', () {
      expect(ApiConstants.isLocalUrl(ApiConstants.debugDefaultBaseUrl), isTrue);
      expect(
        ApiConstants.resolveBaseUrl(configuredUrl: '', releaseMode: false),
        ApiConstants.debugDefaultBaseUrl,
      );
      expect(
        ApiConstants.resolveBaseUrl(configuredUrl: '', releaseMode: true),
        isEmpty,
      );
      expect(
        ApiConstants.releaseUrlProblem(ApiConstants.debugDefaultBaseUrl),
        isNotNull,
      );
    });
  });
}
