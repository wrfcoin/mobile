import 'package:dio/dio.dart';

import 'station_submit_token_store.dart';

/// Only the exact backend weather-submit path receives this credential.
/// Oracle uploads retain JWT + phone signatures; station tokens never replace
/// those credentials, leak to another origin, or trigger wallet-login retries.
class StationSubmitAuthInterceptor extends Interceptor {
  StationSubmitAuthInterceptor(this._dio, this._store);
  final Dio _dio;
  final StationSubmitTokenStore _store;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.extra.remove('stationSubmitAuth');
    final base = Uri.parse(_dio.options.baseUrl);
    final uri = options.uri;
    if (options.method != 'POST' ||
        uri.path != '/api/weather/submit' ||
        uri.origin != base.origin) {
      handler.next(options);
      return;
    }
    options.extra['stationSubmitAuth'] = true;
    options.extra['noRetry'] = true;
    options.extra['noAuthRetry'] = true;
    options.headers = {
      for (final entry in options.headers.entries)
        if (entry.key.toLowerCase() != 'authorization') entry.key: entry.value,
    };
    try {
      if (uri.scheme != 'https') throw StateError('Secure transport required.');
      final body = options.data;
      if (body is! Map) throw StateError('Missing station.');
      final stationId = body['stationId'] ?? body['station_id'];
      if (stationId is! String ||
          (body['stationId'] != null &&
              body['station_id'] != null &&
              body['stationId'] != body['station_id'])) {
        throw StateError('Missing station.');
      }
      final token = await _store.read(stationId);
      if (token == null) throw StateError('Missing station credential.');
      options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    } catch (_) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          message: 'Import this station credential before weather submission.',
        ),
      );
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.requestOptions.extra['stationSubmitAuth'] == true) {
      err.requestOptions.headers = {
        for (final entry in err.requestOptions.headers.entries)
          if (entry.key.toLowerCase() != 'authorization')
            entry.key: entry.value,
      };
    }
    handler.next(err);
  }
}
