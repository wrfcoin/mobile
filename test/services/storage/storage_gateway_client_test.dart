import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/storage/storage_gateway_client.dart';

void main() {
  group('StorageGatewayClient', () {
    test(
      'falls back from IPFS to Arweave when the first gateway fails',
      () async {
        final attempts = <String>[];
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              attempts.add(options.uri.path);

              if (options.uri.path.startsWith('/ipfs/')) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 503,
                      data: 'ipfs unavailable',
                    ),
                    type: DioExceptionType.badResponse,
                  ),
                );
                return;
              }

              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: Uint8List.fromList(
                    utf8.encode('{"stationId":"wrf-01","temperature":24.2}'),
                  ),
                ),
              );
            },
          ),
        );

        final client = StorageGatewayClient(
          dio: dio,
          ipfsGateways: ['https://ipfs.example.com'],
          arweaveGateways: ['https://arweave.example.com'],
        );

        final observation = await client.fetchWeatherObservation(
          'QmWeatherCid',
        );

        expect(attempts, ['/ipfs/QmWeatherCid', '/QmWeatherCid']);
        expect(
          utf8.decode(observation),
          '{"stationId":"wrf-01","temperature":24.2}',
        );
      },
    );
  });
}
