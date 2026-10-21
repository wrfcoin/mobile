import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/dio_error_mapper.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';

DioException _exception(DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: '/weather/observations'),
  type: type,
);

void main() {
  group('DioErrorMapper', () {
    // dio 5.10 added `transformTimeout`, which made the mapper's switch
    // non-exhaustive and broke the build. The analyzer enforces that a new
    // enum member is handled at all; this pins *how* it is handled.
    test('maps transformTimeout to a server-slowness failure', () {
      final failure = DioErrorMapper.map(
        _exception(DioExceptionType.transformTimeout),
      );

      expect(failure, isA<ServerFailure>());
      expect(failure.message, 'Server took too long to respond.');
    });

    // Controls: without these, the assertion above could pass simply because
    // every branch returned a ServerFailure with the same message.
    test('maps connectionTimeout to a network failure, not a server one', () {
      final failure = DioErrorMapper.map(
        _exception(DioExceptionType.connectionTimeout),
      );

      expect(failure, isA<NetworkFailure>());
      expect(failure, isNot(isA<ServerFailure>()));
    });

    test('maps badCertificate to a security failure', () {
      final failure = DioErrorMapper.map(
        _exception(DioExceptionType.badCertificate),
      );

      expect(failure, isA<SecurityFailure>());
    });

    test('maps a 401 response to an auth failure', () {
      final failure = DioErrorMapper.map(
        DioException(
          requestOptions: RequestOptions(path: '/auth/me'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/auth/me'),
            statusCode: 401,
          ),
        ),
      );

      expect(failure, isA<AuthFailure>());
      expect(failure.message, 'Not signed in. Tap Sign in to continue.');
    });
  });
}
