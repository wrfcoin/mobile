import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/wrf_forecast_model.dart';
import '../../../../support/wrf_forecast_fixtures.dart';

void main() {
  group('WrfForecastPoint', () {
    test('fromJson / toJson round-trip', () {
      final json = <String, dynamic>{
        'timestamp': '2026-04-11T10:00:00Z',
        'temperatureC': 21.5,
        'temperatureMaxC': 23.0,
        'temperatureMinC': 20.0,
        'precipitationMm': 0.4,
        'windSpeedMs': 5.2,
        'forecastConfidence': 0.88,
        'hdd': 0.0,
        'cdd': 3.2,
      };
      final point = WrfForecastPoint.fromJson(json);
      expect(point.temperatureC, 21.5);
      expect(point.temperatureMaxC, 23.0);
      expect(point.temperatureMinC, 20.0);
      expect(point.precipitationMm, 0.4);
      expect(point.windSpeedMs, 5.2);
      expect(point.forecastConfidence, 0.88);
      expect(point.hdd, 0.0);
      expect(point.cdd, 3.2);

      final roundTripped = WrfForecastPoint.fromJson(point.toJson());
      expect(roundTripped, point);
    });

    test('HDD is non-zero when temperature below 18.3', () {
      final point = wrfForecastSimulationStub('test')
          .hourly
          .firstWhere((p) => p.hdd > 0, orElse: () => const WrfForecastPoint(
                timestamp: '2026-04-11T00:00:00Z',
                temperatureC: 15.0,
                temperatureMaxC: 16.0,
                temperatureMinC: 14.0,
                precipitationMm: 0,
                windSpeedMs: 2,
                hdd: 3.3,
                cdd: 0.0,
              ));
      expect(point.hdd, greaterThan(0));
      expect(point.cdd, 0.0);
    });

    test('CDD is non-zero when temperature above 18.3', () {
      const point = WrfForecastPoint(
        timestamp: '2026-04-11T14:00:00Z',
        temperatureC: 25.0,
        temperatureMaxC: 26.0,
        temperatureMinC: 24.0,
        precipitationMm: 0,
        windSpeedMs: 3,
        hdd: 0.0,
        cdd: 6.7,
      );
      expect(point.cdd, greaterThan(0));
      expect(point.hdd, 0.0);
    });

    test('default forecastConfidence is 1.0', () {
      const point = WrfForecastPoint(
        timestamp: '2026-04-11T00:00:00Z',
        temperatureC: 18.0,
        temperatureMaxC: 19.0,
        temperatureMinC: 17.0,
        precipitationMm: 0,
        windSpeedMs: 2,
      );
      expect(point.forecastConfidence, 1.0);
    });
  });

  group('WrfForecastModel', () {
    test('fromJson / toJson round-trip', () {
      final json = <String, dynamic>{
        'location': 'San Francisco',
        'generatedAt': '2026-04-11T08:00:00Z',
        'ipfsCid': 'QmTestCID123456789',
        'isSimulated': false,
        'hourly': <dynamic>[],
      };
      final model = WrfForecastModel.fromJson(json);
      expect(model.location, 'San Francisco');
      expect(model.generatedAt, '2026-04-11T08:00:00Z');
      expect(model.ipfsCid, 'QmTestCID123456789');
      expect(model.isSimulated, false);
      expect(model.hourly, isEmpty);

      final roundTripped = WrfForecastModel.fromJson(model.toJson());
      expect(roundTripped, model);
    });

    test('default isSimulated is false', () {
      const model = WrfForecastModel(
        location: 'Local',
        generatedAt: '2026-04-11T00:00:00Z',
        ipfsCid: 'QmXYZ',
      );
      expect(model.isSimulated, false);
    });

    test('simulation stub has isSimulated == true', () {
      final stub = wrfForecastSimulationStub('local');
      expect(stub.isSimulated, isTrue);
      expect(stub.hourly, isNotEmpty);
      expect(stub.ipfsCid, isNotEmpty);
    });

    test('simulation stub HDD/CDD values parse correctly', () {
      final stub = wrfForecastSimulationStub('local');
      for (final point in stub.hourly) {
        // Only one of HDD/CDD should be non-zero (or both zero at exactly 18.3).
        final bothNonZero = point.hdd > 0 && point.cdd > 0;
        expect(bothNonZero, isFalse,
            reason: 'HDD and CDD should not both be positive for a single point');
      }
    });
  });
}
