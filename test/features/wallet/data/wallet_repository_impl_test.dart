import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

void main() {
  test('send conflict explains pending transfer and never retries', () async {
    final signer = await Ed25519TransferSigner.fromSeedHex('07' * 32);
    final from = WalletSetupService().chainAddressFromEd25519(signer.publicKey);
    final calls = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls.add(options);
          if (options.method == 'GET') {
            handler.resolve(
              Response(requestOptions: options, data: {'nonce': '0'}),
            );
          } else {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: options,
                  statusCode: 409,
                  data: {
                    'error': {
                      'code': 'CONFLICT',
                      'message': 'raw replay sentinel',
                    },
                  },
                ),
              ),
            );
          }
        },
      ),
    );
    final result = await WalletRepositoryImpl(WalletRemoteDataSource(dio))
        .sendTransaction(
          from: from,
          to: '0x${'2' * 40}',
          amountBaseUnits: '150000000',
          signer: signer,
        );
    result.fold((failure) {
      expect(failure.statusCode, 409);
      expect(
        failure.message,
        'Previous transfer still pending; try again after it confirms',
      );
    }, (_) => fail('Conflict must not report success'));
    expect(calls.map((r) => r.method), ['GET', 'POST']);
    expect((calls.last.data as Map)['amount'], '150000000');
  });
  test(
    'WalletRepositoryImpl maps a non-20-byte address into ServerFailure',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: const <dynamic>['invalid-payload'],
              ),
            );
          },
        ),
      );

      final repository = WalletRepositoryImpl(WalletRemoteDataSource(dio));
      final result = await repository.getWallet('wrf1wallet');

      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(
            failure.message,
            contains('address must be exactly 40 hex digits'),
          );
        },
        (_) {
          fail('Expected wallet failure for an invalid address');
        },
      );
    },
  );
}
