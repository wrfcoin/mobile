import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/dio_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../services/api/api_client.dart';
import '../models/alert_model.dart';
import '../models/current_conditions_model.dart';
import '../models/forecast_detail_model.dart';
import '../models/forecast_model.dart';
import '../models/weather_envelopes.dart';
import '../models/wrf_forecast_model.dart';
import '../../domain/models/coarse_location.dart';

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository(ref.watch(apiClientProvider).dio);
});

class WeatherRepository {
  final Dio _dio;

  WeatherRepository(this._dio);

  /// Active alerts for [location] (`GET /weather/alerts/:lat,lon`).
  Future<Either<Failure, List<AlertModel>>> getActiveAlerts(
    CoarseLocation location,
  ) async {
    try {
      final response = await _dio.get(
        ApiConstants.weatherAlerts(location.pathSegment),
      );
      final alerts = alertsFromEnvelope(response.data);
      if (alerts == null) {
        return const Left(ServerFailure('Unexpected weather alerts response'));
      }
      return Right(alerts);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, ForecastModel>> getRealtimeData(
    String stationId,
  ) async {
    try {
      final response = await _dio.get(ApiConstants.weatherRealtime(stationId));
      return Right(
        ForecastModel.fromJson(response.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Current forecast for [location] (`GET /weather/forecast/:lat,lon`).
  ///
  /// The public edge admits only its exact queries here, and answers 404 to
  /// a request with none, so the query is part of the route.
  ///
  /// An envelope without forecast periods is unavailable, never a model of
  /// zeros.
  Future<Either<Failure, ForecastModel>> getForecast(
    CoarseLocation location,
  ) async {
    try {
      final response = await _dio.get(
        ApiConstants.weatherForecast(location.pathSegment),
        queryParameters: ApiConstants.weatherForecastDailyQuery,
      );
      final forecast = forecastFromEnvelope(response.data);
      if (forecast == null) {
        return const Left(
          NotAvailableFailure(
            'No forecast is available for your area right now.',
          ),
        );
      }
      return Right(forecast);
    } on DioException catch (e) {
      return Left(_forecastFailure(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// The latest observation for [location]
  /// (`GET /weather/current/:lat,lon`, mobile#332). An unexpected envelope is
  /// unavailable, never a model of zeros.
  Future<Either<Failure, CurrentConditions>> getCurrentConditions(
    CoarseLocation location,
  ) async {
    try {
      final response = await _dio.get(
        ApiConstants.weatherCurrent(location.pathSegment),
      );
      final current = currentFromEnvelope(response.data);
      if (current == null) {
        return const Left(
          NotAvailableFailure('No current conditions are available right now.'),
        );
      }
      return Right(current);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// The forecast detail for [location], from the mounted
  /// `GET /weather/forecast/:lat,lon` (mobile#270): its hourly periods
  /// (`?type=hourly`) and its daily periods, requested together.
  ///
  /// A half that fails or has no periods is null in the result (shown as
  /// "not available"); only when neither half is available is it a [Left].
  Future<Either<Failure, ForecastDetail>> getForecastDetail(
    CoarseLocation location,
  ) async {
    final path = ApiConstants.weatherForecast(location.pathSegment);
    final (hourly, daily) = await (
      _getPayload(path, ApiConstants.weatherForecastHourlyQuery),
      _getPayload(path, ApiConstants.weatherForecastDailyQuery),
    ).wait;
    final hours = hourly.fold((_) => null, hourlyFromEnvelope);
    final days = daily.fold((_) => null, dailyFromEnvelope);
    if (hours == null && days == null) {
      return Left(
        daily.fold(
          (failure) => failure,
          (_) => hourly.fold(
            (failure) => failure,
            (_) => const NotAvailableFailure(
              'No forecast is available for your area right now.',
            ),
          ),
        ),
      );
    }
    return Right(ForecastDetail(hourly: hours, daily: days));
  }

  /// A 404 here means no forecast is reachable; the edge's bare "Not found"
  /// says nothing useful to a person.
  static Failure _forecastFailure(DioException e) =>
      e.response?.statusCode == 404
      ? const NotAvailableFailure(
          'No forecast is available for your area right now.',
        )
      : DioErrorMapper.map(e);

  Future<Either<Failure, Object?>> _getPayload(
    String path,
    Map<String, Object> query,
  ) async {
    try {
      final response = await _dio.get(path, queryParameters: query);
      return Right(response.data);
    } on DioException catch (e) {
      return Left(_forecastFailure(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Fetches real WRF model output for [location] from the IPFS pipeline.
  ///
  /// Returns the server's [WrfForecastModel] on success. On a [Left], callers
  /// show an unavailable state; they must never substitute device-generated
  /// values (mobile#269).
  Future<Either<Failure, WrfForecastModel>> getWrfForecast(
    CoarseLocation location,
  ) async {
    try {
      final response = await _dio.get(
        ApiConstants.wrfForecast(location.pathSegment),
      );
      return Right(
        WrfForecastModel.fromJson(response.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
