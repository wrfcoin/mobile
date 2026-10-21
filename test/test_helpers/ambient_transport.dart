import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';

const ambientKeys = ['synthetic-api-secret', 'synthetic-app-secret'];
const ambientDevices = {
  'valid': true,
  'devices': [
    {'mac': 'AA:BB:CC:DD:EE:01', 'name': 'synthetic-api-secret'},
    {'mac': 'AA-BB-CC-DD-EE-02', 'latitude': 12.345678},
  ],
};
const ambientReceipt = {
  'success': true,
  'provider': 'ambient',
  'stationId': 'station_synthetic',
};

class AmbientTransport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final cancelled = <String>[];
  Object? payload = ambientDevices;
  int status = 200;
  Future<Object?> Function(RequestOptions)? respond;

  ApiClient client({bool authenticated = true}) => ApiClient(
    dio: Dio(BaseOptions(baseUrl: 'https://backend.invalid/api'))
      ..httpClientAdapter = this,
    allowUnauthenticatedRequests: authenticated,
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    cancelFuture?.then((_) => cancelled.add(options.path));
    final body = respond == null ? payload : await respond!(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
