import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/calibration/data/station_calibration.dart';
import 'package:wrfcoin_mobile/features/calibration/presentation/station_calibration_card.dart';
import 'package:wrfcoin_mobile/features/calibration/presentation/station_calibration_screen.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';

import 'calibration_fixtures.dart';

class _Server implements HttpClientAdapter {
  _Server(this.answer);
  final ResponseBody Function(RequestOptions options) answer;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return answer(options);
  }
}

ResponseBody _json(Object data, int status) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

(StationCalibrationRepository, _Server) _repo(
  ResponseBody Function(RequestOptions options) answer,
) {
  final server = _Server(answer);
  final dio = Dio(BaseOptions(baseUrl: 'https://test.example/api'))
    ..httpClientAdapter = server;
  return (StationCalibrationRepository(dio), server);
}

void main() {
  group('reading the answer', () {
    test('a valid certificate parses in full', () {
      final view = StationCalibration.fromJson(calibratedJson());
      expect(view.status, CalibrationStatus.calibrated);
      expect(view.certificate?.issuerId, 'wrfcoin-owner-testnet');
      expect(view.certificate?.sensor, 'Davis 6152');
      expect(view.signedCertificate, isNotNull);
    });

    test('the live "none" answer parses', () {
      final view = StationCalibration.fromJson(noneJson());
      expect(view.status, CalibrationStatus.none);
      expect(view.certificate, isNull);
    });

    test('a revocation keeps its reason', () {
      final view = StationCalibration.fromJson(revokedJson());
      expect(view.status, CalibrationStatus.revoked);
      expect(view.certificate?.revocation?.reason, 'sensor_moved');
    });

    test('anything off contract is refused, never "calibrated"', () {
      final bad = <Object?>[
        null,
        'calibrated',
        {...calibratedJson(), 'status': 'great'},
        {...calibratedJson(), 'checkedAt': 'soon'},
        {...calibratedJson(), 'trustRoots': null},
        {...calibratedJson(), 'certificate': null},
        {
          ...calibratedJson(),
          'certificate': {...certificateJson(), 'status': 'expired'},
        },
        {
          ...calibratedJson(),
          'certificate': {...certificateJson(), 'issuer': null},
        },
        {
          ...calibratedJson(),
          'certificate': {...certificateJson(), 'expiresAt': 'never'},
        },
        {...noneJson(), 'certificate': certificateJson()},
      ];
      for (final body in bad) {
        expect(
          () => StationCalibration.fromJson(body),
          throwsFormatException,
          reason: '$body',
        );
      }
    });
  });

  group('asking the server', () {
    test('an alias goes as it is, with no query', () async {
      final (repository, server) = _repo((_) => _json(noneJson(), 200));
      final result = await repository.forStation('st_7d29a4c1e0b8');
      expect(result.isRight(), isTrue);
      expect(
        server.requests.single.path,
        '/calibration-certificates/station/st_7d29a4c1e0b8',
      );
      expect(server.requests.single.queryParameters, isEmpty);
    });

    test('a raw station id is hashed here and never sent', () async {
      final (repository, server) = _repo((_) => _json(noneJson(), 200));
      await repository.forStation('rooftop-of-a-person');
      final path = server.requests.single.path;
      expect(path, contains(stationAliasOf('rooftop-of-a-person')));
      expect(path, isNot(contains('rooftop')));
    });

    test('a 404 means off; a 503 and a bad body are errors', () async {
      final (off, _) = _repo((_) => ResponseBody.fromString('Not found', 404));
      expect(
        (await off.forStation('st_7d29a4c1e0b8')).getLeft().toNullable(),
        isA<NotAvailableFailure>(),
      );
      final (down, _) = _repo((_) => _json({'error': {}}, 503));
      expect(
        (await down.forStation('st_7d29a4c1e0b8')).getLeft().toNullable(),
        isA<ServerFailure>(),
      );
      final (odd, _) = _repo((_) => _json({'status': 'calibrated'}, 200));
      expect(
        (await odd.forStation('st_7d29a4c1e0b8')).getLeft().toNullable(),
        isA<ServerFailure>(),
      );
    });
  });

  group('card', () {
    Future<void> pump(
      WidgetTester tester,
      Future<Either<Failure, StationCalibration>> Function() answer, {
      bool hideWhenOff = false,
    }) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationCalibrationProvider('st_7d29a4c1e0b8')
                .overrideWith((ref) => answer()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StationCalibrationCard(
                  stationId: 'st_7d29a4c1e0b8',
                  hideWhenOff: hideWhenOff,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<Either<Failure, StationCalibration>> ok(Object json) async =>
        Right(StationCalibration.fromJson(json));

    testWidgets('loaded: the certificate and its details', (tester) async {
      await pump(tester, () => ok(calibratedJson()));
      expect(find.text('Calibrated'), findsOneWidget);
      expect(find.text('wrfcoin-owner-testnet'), findsOneWidget);
      expect(find.text('Oct 1, 2026 to Oct 1, 2027'), findsOneWidget);
      expect(find.text('Davis 6152'), findsOneWidget);
      expect(find.text('0xaaaa…aaaa'), findsOneWidget);
    });

    testWidgets('the signed certificate copies as JSON', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester, () => ok(calibratedJson()));
      await tester.tap(find.text('Copy the signed certificate'));
      await tester.pump();
      expect(jsonDecode(copied!), certificateJson()['artifact']);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('empty: no certificate is said plainly', (tester) async {
      await pump(tester, () => ok(noneJson()));
      expect(find.text('Not calibrated'), findsOneWidget);
      expect(
        find.text(
          'No calibration certificate has been issued for this station yet.',
        ),
        findsOneWidget,
      );
      expect(find.text('Signed by'), findsNothing);
    });

    testWidgets('revoked: shows why', (tester) async {
      await pump(tester, () => ok(revokedJson()));
      expect(find.text('Calibration revoked'), findsOneWidget);
      expect(find.textContaining('the sensor was moved'), findsOneWidget);
    });

    testWidgets('error: never implies "not calibrated"', (tester) async {
      await pump(
        tester,
        () async => const Left(ServerFailure('down', statusCode: 503)),
      );
      expect(find.textContaining('is not available right now'), findsOneWidget);
      expect(find.text('Not calibrated'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('loading: says it is checking', (tester) async {
      await pump(
        tester,
        () => Future.delayed(
          const Duration(days: 1),
          () => const Left(NetworkFailure()),
        ),
      );
      expect(find.text('Checking calibration…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(days: 2));
    });

    testWidgets('off: said on the lookup, hidden on a station page', (
      tester,
    ) async {
      Future<Either<Failure, StationCalibration>> off() async => const Left(
        NotAvailableFailure('Not switched on here.', statusCode: 404),
      );
      await pump(tester, off);
      expect(find.text('Not switched on here.'), findsOneWidget);
      await pump(tester, off, hideWhenOff: true);
      expect(find.text('Sensor calibration'), findsNothing);
    });

    testWidgets('badge: silent for none, named for a certificate', (
      tester,
    ) async {
      Future<void> badge(Object json) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              stationCalibrationProvider('st_7d29a4c1e0b8')
                  .overrideWith((ref) => ok(json)),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: CalibrationBadge(stationId: 'st_7d29a4c1e0b8'),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await badge(noneJson());
      expect(find.byType(Text), findsNothing);
      await badge(calibratedJson());
      expect(find.text('Calibrated'), findsOneWidget);
    });
  });

  group('lookup screen', () {
    testWidgets('opens on this phone\'s station, looks up another alias', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            phoneStationIdProvider.overrideWith((ref) async => 'phone-station'),
            stationCalibrationProvider('phone-station').overrideWith(
              (ref) async => Right(StationCalibration.fromJson(noneJson())),
            ),
            stationCalibrationProvider('st_7d29a4c1e0b8').overrideWith(
              (ref) async =>
                  Right(StationCalibration.fromJson(calibratedJson())),
            ),
          ],
          child: const MaterialApp(home: StationCalibrationScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("This phone's station: st_"), findsOneWidget);
      expect(find.text('Not calibrated'), findsOneWidget);

      final lookUp = find.widgetWithText(FilledButton, 'Look up');
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.pump();
      expect(tester.widget<FilledButton>(lookUp).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'ST_7D29A4C1E0B8');
      await tester.pump();
      await tester.tap(lookUp);
      await tester.pumpAndSettle();
      expect(find.text('Station st_7d29a4c1e0b8'), findsOneWidget);
      expect(find.text('Calibrated'), findsOneWidget);
    });

    testWidgets('without a wallet it asks for an alias', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [phoneStationIdProvider.overrideWith((ref) async => null)],
          child: const MaterialApp(home: StationCalibrationScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a station alias to check its calibration.'),
        findsOneWidget,
      );
    });
  });
}
