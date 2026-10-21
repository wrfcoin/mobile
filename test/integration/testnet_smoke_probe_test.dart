import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';

// Default-suite probes always bind their own loopback server. Operator-only
// checks live separately under integration_test/ and require explicit opt-in.
const _walletAddress = '0x2222222222222222222222222222222222222222';
const _weatherSubmitPath = ApiConstants.oracleSubmitData;
const _nodeStatusPath = '/node/status';

void main() {
  late _SmokeTarget target;
  late Dio dio;

  setUpAll(() async {
    target = await _SmokeTarget.create();
    dio = Dio(
      BaseOptions(
        baseUrl: target.baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (_) => true,
      ),
    );
  });

  tearDownAll(() async {
    dio.close(force: true);
    await target.close();
  });

  group('testnet smoke', () {
    test('wallet balance fetch returns shape-valid JSON', () async {
      final payload = await _getMap(
        dio,
        ApiConstants.walletInfo(_walletAddress),
        scenario: 'wallet-balance',
      );
      final wallet = _unwrapDataMap(payload);

      expect(
        wallet['address']?.toString(),
        isNotEmpty,
        reason: 'RESPONSE_SHAPE_REGRESSION: wallet response lacks address',
      );
      expect(
        wallet.containsKey('balance') || wallet.containsKey('tokens'),
        isTrue,
        reason:
            'RESPONSE_SHAPE_REGRESSION: wallet response lacks balance/tokens',
      );
    });

    test('weather submission accepts shape-valid payload', () async {
      final payload = await _postMap(
        dio,
        _weatherSubmitPath,
        data: <String, Object?>{
          'stationId': 'mobile-smoke-01',
          'walletAddress': _walletAddress,
          'temperatureC': 21.4,
          'humidityPercent': 48.0,
          'windSpeedMps': 2.3,
          'observedAt': '2026-05-29T00:00:00Z',
        },
        scenario: 'weather-submit',
      );

      expect(
        payload.isNotEmpty,
        isTrue,
        reason: 'RESPONSE_SHAPE_REGRESSION: weather submit response is empty',
      );
    });

    test('node status exposes block height or ready state', () async {
      final payload = await _getMap(
        dio,
        _nodeStatusPath,
        scenario: 'node-status',
      );
      final status = _unwrapDataMap(payload);

      expect(
        status.containsKey('height') ||
            status.containsKey('blockHeight') ||
            status.containsKey('latestBlock') ||
            status.containsKey('ready'),
        isTrue,
        reason:
            'RESPONSE_SHAPE_REGRESSION: node status lacks height/ready fields',
      );
    });
  });
}

Future<Map<String, dynamic>> _getMap(
  Dio dio,
  String path, {
  required String scenario,
}) async {
  final response = await _request(
    () => dio.get<dynamic>(path),
    scenario: scenario,
  );
  return _responseMap(response, scenario: scenario);
}

Future<Map<String, dynamic>> _postMap(
  Dio dio,
  String path, {
  required Map<String, Object?> data,
  required String scenario,
}) async {
  final response = await _request(
    () => dio.post<dynamic>(path, data: data),
    scenario: scenario,
  );
  return _responseMap(response, scenario: scenario);
}

Future<Response<dynamic>> _request(
  Future<Response<dynamic>> Function() request, {
  required String scenario,
}) async {
  try {
    final response = await request();
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      fail(
        'RESPONSE_SHAPE_REGRESSION: $scenario returned HTTP $status '
        'from ${response.realUri}',
      );
    }
    return response;
  } on DioException catch (error) {
    fail(
      'TESTNET_DOWN: $scenario could not reach ${error.requestOptions.uri}: '
      '${error.type} ${error.message}',
    );
  }
}

Map<String, dynamic> _responseMap(
  Response<dynamic> response, {
  required String scenario,
}) {
  final data = response.data;
  if (data is Map) return Map<String, dynamic>.from(data);

  fail(
    'RESPONSE_SHAPE_REGRESSION: $scenario expected JSON object, got '
    '${data.runtimeType}',
  );
}

Map<String, dynamic> _unwrapDataMap(Map<String, dynamic> payload) {
  final data = payload['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  return payload;
}

class _SmokeTarget {
  _SmokeTarget._({required this.baseUrl, this.server});

  final String baseUrl;
  final HttpServer? server;

  static Future<_SmokeTarget> create() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handleStubRequest);
    return _SmokeTarget._(
      baseUrl: 'http://${server.address.host}:${server.port}/api',
      server: server,
    );
  }

  Future<void> close() async {
    await server?.close(force: true);
  }
}

Future<void> _handleStubRequest(HttpRequest request) async {
  final path = request.uri.path;
  request.response.headers.contentType = ContentType.json;

  if (request.method == 'GET' && path.endsWith('/wallet/$_walletAddress')) {
    await _writeJson(request, <String, Object?>{
      'data': <String, Object?>{
        'address': _walletAddress,
        'balance': '1.000',
        'transactions': 0,
      },
    });
    return;
  }

  if (request.method == 'POST' &&
      (path.endsWith(_weatherSubmitPath) || path.endsWith('/weather/submit'))) {
    await utf8.decoder.bind(request).join();
    request.response.statusCode = HttpStatus.created;
    await _writeJson(request, const <String, Object?>{
      'success': true,
      'data': <String, Object?>{'accepted': true},
    });
    return;
  }

  if (request.method == 'GET' && path.endsWith(_nodeStatusPath)) {
    await _writeJson(request, const <String, Object?>{
      'data': <String, Object?>{'blockHeight': 1555, 'ready': true},
    });
    return;
  }

  request.response.statusCode = HttpStatus.notFound;
  await _writeJson(request, <String, Object?>{
    'error': 'stub route not found',
    'path': path,
  });
}

Future<void> _writeJson(
  HttpRequest request,
  Map<String, Object?> payload,
) async {
  request.response.write(jsonEncode(payload));
  await request.response.close();
}
