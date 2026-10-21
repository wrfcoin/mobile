import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/dio_error_mapper.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';

void main() {
  test('maps the backend honest 501 envelope to NotAvailableFailure', () {
    final request = RequestOptions(path: '/wallet/0xabc/transactions');
    final failure = DioErrorMapper.map(
      DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 501,
          data: const {
            'error': {
              'message': 'Wallet transaction history is unavailable on this node version.',
              'details': 'capability: wallet.history',
            },
          },
        ),
      ),
    );

    expect(failure, isA<NotAvailableFailure>());
    expect(failure.message, contains('unavailable'));
    expect((failure as NotAvailableFailure).detail, contains('wallet.history'));
  });

  test('keeps a 500 as a real server failure', () {
    final request = RequestOptions(path: '/wallet/0xabc/transactions');
    final failure = DioErrorMapper.map(
      DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: request, statusCode: 500),
      ),
    );
    expect(failure, isA<ServerFailure>());
    expect(failure, isNot(isA<NotAvailableFailure>()));
  });

  Failure map503(Map<String, dynamic> body) {
    final request = RequestOptions(path: '/wallet/0xabc/transactions');
    return DioErrorMapper.map(
      DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 503,
          data: body,
        ),
      ),
    );
  }

  test('maps the reader-credential 503 to NotAvailableFailure by code', () {
    // Exact body from backend#1199 requireReaderToken().
    final failure = map503(const {
      'success': false,
      'error': {
        'code': 'CORE4_READER_CREDENTIAL_UNCONFIGURED',
        'message': 'Wallet chain reads are unavailable: the backend core4 Reader credential is not configured',
      },
      'timestamp': '2026-09-23T00:00:00.000Z',
    });

    expect(failure, isA<NotAvailableFailure>());
    expect(failure.statusCode, 503);
    expect(
      (failure as NotAvailableFailure).detail,
      'CORE4_READER_CREDENTIAL_UNCONFIGURED',
    );
  });

  test('keeps any other 503 a transient server failure', () {
    final failure = map503(const {
      'error': {'code': 'CORE4_UNAVAILABLE', 'message': 'core4 down'},
    });
    expect(failure, isA<ServerFailure>());
  });
}
