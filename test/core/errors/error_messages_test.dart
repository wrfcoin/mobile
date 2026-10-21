import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/error_messages.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';

void main() {
  group('ErrorMessages.fromFailure', () {
    test('maps NetworkFailure', () {
      expect(
        ErrorMessages.fromFailure(const NetworkFailure()),
        contains('internet'),
      );
    });

    test('maps AuthFailure', () {
      expect(
        ErrorMessages.fromFailure(const AuthFailure()),
        contains('Session expired'),
      );
    });

    test('maps CacheFailure', () {
      expect(
        ErrorMessages.fromFailure(const CacheFailure()),
        contains('Local storage'),
      );
    });

    test('maps ValidationFailure with custom message', () {
      expect(
        ErrorMessages.fromFailure(const ValidationFailure('Bad input')),
        'Bad input',
      );
    });

    test('maps ServerFailure 400', () {
      expect(
        ErrorMessages.fromFailure(const ServerFailure('x', statusCode: 400)),
        contains('Invalid'),
      );
    });

    test('maps ServerFailure 401', () {
      expect(
        ErrorMessages.fromFailure(const ServerFailure('x', statusCode: 401)),
        contains('Session expired'),
      );
    });

    test('maps ServerFailure 403', () {
      expect(
        ErrorMessages.fromFailure(const ServerFailure('x', statusCode: 403)),
        contains('denied'),
      );
    });

    test('maps ServerFailure 404', () {
      expect(
        ErrorMessages.fromFailure(const ServerFailure('x', statusCode: 404)),
        contains('Not found'),
      );
    });

    test('maps ServerFailure 429', () {
      expect(
        ErrorMessages.fromFailure(const ServerFailure('x', statusCode: 429)),
        contains('many requests'),
      );
    });

    test('maps ServerFailure 500', () {
      expect(
        ErrorMessages.fromFailure(const ServerFailure('x', statusCode: 500)),
        contains('Server error'),
      );
    });

    test('maps ServerFailure 503', () {
      expect(
        ErrorMessages.fromFailure(const ServerFailure('x', statusCode: 503)),
        contains('Server error'),
      );
    });

    test('maps ServerFailure with no status code uses message', () {
      expect(
        ErrorMessages.fromFailure(const ServerFailure('Custom backend error')),
        'Custom backend error',
      );
    });
  });
}
