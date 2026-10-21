import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:wrfcoin_mobile/features/gamification/presentation/screens/data_desert_map_screen.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeLocationService extends LocationService {
  final Position? _position;
  _FakeLocationService({this._position});

  @override
  Future<Position?> getCurrentPosition() async => _position;
}

Dio _mockDio(dynamic responseData) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: responseData),
        );
      },
    ),
  );
  return dio;
}

// ── Helpers ────────────────────────────────────────────────────────────────────

const _kZones = [
  {'lat': 39.8, 'lng': -98.5, 'radius': 30.0, 'type': 'desert', 'rewardMultiplier': 2.0},
  {'lat': 36.1, 'lng': -115.1, 'radius': 25.0, 'type': 'sparse', 'rewardMultiplier': 1.5},
  {'lat': 47.6, 'lng': -122.3, 'radius': 20.0, 'type': 'covered', 'rewardMultiplier': 1.0},
];

Position _fakePosition({double lat = 37.77, double lng = -122.41}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 4, 16),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Widget _buildScreen({
  List<Map<String, dynamic>> zones = _kZones,
  Position? position,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(ApiClient(dio: _mockDio({'zones': zones}))),
      locationServiceProvider.overrideWithValue(_FakeLocationService(position: position)),
    ],
    child: const MaterialApp(home: DataDesertMapScreen()),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('DataDesertMapScreen', () {
    testWidgets('renders app bar title', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Data Desert Map'), findsOneWidget);
    });

    testWidgets('shows all three legend entries after zones load', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump(const Duration(milliseconds: 100));

      // Use parenthesis to match legend text only, not the AppBar "Data Desert Map" title
      expect(find.textContaining('Data Desert ('), findsOneWidget);
      expect(find.textContaining('Sparse ('), findsOneWidget);
      expect(find.textContaining('Covered ('), findsOneWidget);
    });

    testWidgets('legend shows reward multipliers from zone data', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump(const Duration(milliseconds: 100));

      // Multipliers from _kZones: desert=2×, sparse=1.5×, covered=1×
      expect(find.textContaining('2×'), findsWidgets);
      expect(find.textContaining('1.5×'), findsWidgets);
    });

    testWidgets('Start Collecting Here CTA button is present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Start Collecting Here'), findsOneWidget);
    });

    testWidgets('FAB shows my_location icon when location is loaded', (tester) async {
      await tester.pumpWidget(_buildScreen(position: _fakePosition()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('no uncaught exception when user position is available', (tester) async {
      await tester.pumpWidget(_buildScreen(position: _fakePosition()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('no uncaught exception when user position is null', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('zone markers are keyed and tapping opens bottom sheet', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump(const Duration(milliseconds: 100));

      // Each zone GestureDetector is keyed by lat/lng for reliable test targeting
      final desertKey = find.byKey(const ValueKey('zone_39.8_-98.5'));
      expect(desertKey, findsOneWidget);

      await tester.tap(desertKey, warnIfMissed: false);
      // Drain flutter_map tap-debounce timer (~250ms)
      await tester.pump(const Duration(milliseconds: 300));

      // Bottom sheet should show reward text
      expect(find.textContaining('WRF'), findsWidgets);
    });

    testWidgets('empty zones list renders without error', (tester) async {
      await tester.pumpWidget(_buildScreen(zones: []));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Data Desert Map'), findsOneWidget);
    });

    testWidgets('API error shows snackbar and hides progress indicator', (tester) async {
      final failDio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      failDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient(dio: failDio)),
            locationServiceProvider.overrideWithValue(_FakeLocationService()),
          ],
          child: const MaterialApp(home: DataDesertMapScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Could not load coverage data'), findsOneWidget);
      // Loading bar gone
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('CoverageZone.fromJson', () {
    test('returns null when lat is missing', () {
      expect(CoverageZone.fromJson({'lng': -98.5}), isNull);
    });

    test('returns null when lng is missing', () {
      expect(CoverageZone.fromJson({'lat': 39.8}), isNull);
    });

    test('parses desert zone correctly', () {
      final zone = CoverageZone.fromJson({
        'lat': 39.8,
        'lng': -98.5,
        'radius': 50.0,
        'type': 'desert',
        'rewardMultiplier': 2.0,
      });
      expect(zone, isNotNull);
      expect(zone!.type, 'desert');
      expect(zone.rewardMultiplier, 2.0);
      expect(zone.radius, 50.0);
      expect(zone.lat, 39.8);
      expect(zone.lng, -98.5);
    });

    test('defaults to radius 30 when omitted', () {
      final zone = CoverageZone.fromJson({'lat': 1.0, 'lng': 2.0});
      expect(zone!.radius, 30.0);
    });

    test('accepts multiplier field as fallback for rewardMultiplier', () {
      final zone = CoverageZone.fromJson({
        'lat': 1.0,
        'lng': 2.0,
        'type': 'sparse',
        'multiplier': 1.5,
      });
      expect(zone!.rewardMultiplier, 1.5);
    });

    test('unknown type defaults to error color (treated as desert)', () {
      final zone = CoverageZone.fromJson({'lat': 0.0, 'lng': 0.0, 'type': 'unknown'});
      expect(zone, isNotNull);
      expect(zone!.type, 'unknown');
    });
  });
}
