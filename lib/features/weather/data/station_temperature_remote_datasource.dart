import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api/api_client.dart';
import '../domain/models/coarse_location.dart';
import '../domain/models/station_temperature.dart';

final stationTemperatureDataSourceProvider =
    Provider<StationTemperatureRemoteDataSource>(
      (ref) =>
          StationTemperatureRemoteDataSource(ref.watch(apiClientProvider).dio),
    );

enum StationTemperatureFetchKind {
  /// A well-formed answer (it may still have no data).
  data,

  /// Not signed in, not allowed, or the route is not deployed yet
  /// (401, 403, 404, 501): show nothing, not an error.
  hidden,

  /// Anything else (a 5xx, a rate limit, a network error, a malformed body).
  unavailable,
}

class StationTemperatureFetch {
  const StationTemperatureFetch(this.kind, [this.history]);

  final StationTemperatureFetchKind kind;
  final StationTemperatureHistory? history;
}

/// `GET /api/weather/temperature-history` (backend#1382). The request carries
/// the 0.1 degree cell as integer tenths only: a [CoarseLocation] is the only
/// accepted input, so nothing finer can be sent.
class StationTemperatureRemoteDataSource {
  StationTemperatureRemoteDataSource(this._dio);

  final Dio _dio;

  static const int days = 14;

  /// Never throws.
  Future<StationTemperatureFetch> fetch(
    CoarseLocation cell, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/weather/temperature-history',
        queryParameters: {
          'latE1': cell.latE1,
          'lonE1': cell.lonE1,
          'days': days,
        },
        cancelToken: cancelToken,
        // No transient retry: the provider bounds this read to the foreground/session,
        // which automatic 5xx retries would bypass (501 included). Auth may renew once.
        options: Options(extra: {'noRetry': true}),
      );
      final data = response.data;
      if (data is Map) {
        return StationTemperatureFetch(
          StationTemperatureFetchKind.data,
          StationTemperatureHistory.fromJson(Map<String, dynamic>.from(data)),
        );
      }
      return const StationTemperatureFetch(
        StationTemperatureFetchKind.unavailable,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403 || status == 404 || status == 501) {
        return const StationTemperatureFetch(
          StationTemperatureFetchKind.hidden,
        );
      }
      return const StationTemperatureFetch(
        StationTemperatureFetchKind.unavailable,
      );
    } catch (_) {
      return const StationTemperatureFetch(
        StationTemperatureFetchKind.unavailable,
      );
    }
  }
}
