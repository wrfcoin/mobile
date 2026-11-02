import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/public_read.dart';
import '../../../../services/api/api_client.dart';
import '../models/forecast_check_model.dart';

/// Answer to a hand-in: [accepted] false means nothing was added.
class HandInResult {
  const HandInResult({required this.accepted, required this.message});
  final bool accepted;
  final String message;
}

final forecastCheckRepositoryProvider = Provider<ForecastCheckRepository>(
  (ref) => ForecastCheckRepository(ref.watch(apiClientProvider).dio),
);

/// The website's forecast check routes (backend
/// forecast-verification-routes.ts, mounted at /api/forecast-verification;
/// the base URL already ends in /api). Public: no wallet or login is needed.
class ForecastCheckRepository {
  ForecastCheckRepository(this._dio);

  final Dio _dio;

  static const summaryPath = '/forecast-verification/summary';
  static const submitPath = '/forecast-verification/forecasts';

  static const _refusals = <String, String>{
    'COMMIT_MISMATCH': 'These files do not hash to that commit id. Paste commit.json and data.json from the same forecast folder, unchanged.',
    'NOT_ON_CHAIN': 'The chain has no commit with this id yet.',
    'NOT_REVEALED': 'Reveal this forecast on chain first, then hand it in.',
    'NOT_A_FORECAST': 'That commit is a station reading, not a forecast.',
    'STATION_MISMATCH':
        'The chain commit names a different station than data.json.',
  };

  static const _busy =
      'Too many requests right now. Please wait a moment and try again.';
  static const _unavailable = 'Forecast check is unavailable right now.';

  Future<PublicRead<ForecastCheckSummary>> getSummary() =>
      readPublicJson(_dio, summaryPath, ForecastCheckSummary.fromJson);

  Future<HandInResult> handIn(ForecastHandIn record) async {
    try {
      final response = await _dio.post<dynamic>(
        submitPath,
        data: record.toJson(),
        options: Options(extra: {'noRetry': true}),
      );
      return HandInResult(
        accepted: true,
        message: response.statusCode == 201
            ? "Added. It is scored once the target hour has passed and the station's readings are on chain."
            : 'This forecast was already handed in.',
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 429) {
        return const HandInResult(accepted: false, message: _busy);
      }
      if (status != null && status >= 400 && status < 500) {
        final body = error.response?.data;
        final problem = body is Map && body['error'] is Map
            ? body['error'] as Map
            : null;
        return HandInResult(
          accepted: false,
          message:
              _refusals[problem?['code']] ??
              jsonText(problem?['message']) ??
              'The server refused this record.',
        );
      }
      return const HandInResult(accepted: false, message: _unavailable);
    }
  }
}
