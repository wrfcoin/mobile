import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/weather_envelopes.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';

/// The real answer to `GET /api/weather/forecast/44.9,-93.3?days=14`, saved
/// from wrfcoin.com on 2026-11-02.
Map<String, dynamic> liveDays14() => jsonDecode(
  File('test/fixtures/forecast_days14_live.json').readAsStringSync(),
) as Map<String, dynamic>;

final _location = CoarseLocation.round(44.9, -93.3);

(WeatherRepository, List<Uri>) repository(
  void Function(RequestOptions, RequestInterceptorHandler) answer,
) {
  final seen = <Uri>[];
  final dio = Dio(BaseOptions(baseUrl: 'https://wrfcoin.test/api'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        seen.add(options.uri);
        answer(options, handler);
      },
    ),
  );
  return (WeatherRepository(dio), seen);
}

void main() {
  test('asks for the exact query the edge admits', () async {
    final (repo, seen) = repository(
      (o, h) => h.resolve(Response(requestOptions: o, data: liveDays14())),
    );
    final result = await repo.getForecast(_location);
    expect(result.isRight(), isTrue);
    expect(seen.single.path, '/api/weather/forecast/${_location.pathSegment}');
    expect(seen.single.query, 'days=14');
  });

  test('every forecast request carries an admitted query', () async {
    final (repo, seen) = repository(
      (o, h) => h.resolve(Response(requestOptions: o, data: liveDays14())),
    );
    await repo.getForecast(_location);
    await repo.getForecastDetail(_location);
    expect(seen, hasLength(3));
    for (final uri in seen) {
      expect(uri.query, anyOf('days=14', 'type=hourly&days=1'));
    }
  });

  test('parses the real ?days=14 answer without inventing values', () {
    final body = liveDays14();
    final first = (body['forecast']['periods'] as List).first as Map;
    final ForecastModel forecast = forecastFromEnvelope(body)!;
    expect(first['temperatureUnit'], 'F');
    expect(
      forecast.temperature,
      closeTo(((first['temperature'] as num) - 32) * 5 / 9, 0.01),
    );
    expect(forecast.windDirection, first['windDirection']);
    expect(forecast.timestamp, first['startTime']);
    expect(forecast.location, forecastAreaLabel);
    // Daily periods give a min-max humidity range, not one reading, so the
    // card shows none rather than picking a figure.
    expect(first['relativeHumidity'], containsPair('min', isA<num>()));
    expect(forecast.humidity, isNull);
  });

  for (final call in ['card', 'detail']) {
    test('$call: a 404 never shows the raw "Not found"', () async {
      final (repo, _) = repository(
        (o, h) => h.reject(
          DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: o,
              statusCode: 404,
              data: 'Not found',
            ),
          ),
        ),
      );
      final failure = call == 'card'
          ? (await repo.getForecast(_location)).getLeft().toNullable()
          : (await repo.getForecastDetail(_location)).getLeft().toNullable();
      expect(failure, isA<NotAvailableFailure>());
      expect(failure!.message, isNot(contains('Not found')));
      expect(
        failure.message,
        'No forecast is available for your area right now.',
      );
    });
  }

  test('other server errors still map normally', () async {
    final (repo, _) = repository(
      (o, h) => h.reject(
        DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: o,
            statusCode: 500,
            data: const {},
          ),
        ),
      ),
    );
    final failure = (await repo.getForecast(_location)).getLeft().toNullable();
    expect(failure, isNot(isA<NotAvailableFailure>()));
  });
}
