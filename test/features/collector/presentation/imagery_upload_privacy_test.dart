// The real imagery screen: a camera or gallery photo with GPS in its EXIF never leaves the device
// with that GPS, and a photo that cannot be sanitized is not uploaded. Synthetic position and pixels.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wrfcoin_mobile/core/localization/app_localizations.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/imagery_upload_screen.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';

import '../../../test_helpers/fakes.dart';
import '../../../test_helpers/gps_jpeg.dart';
import '../../../test_helpers/metadata_fixtures.dart';

class _NoPositionLocation extends LocationService {
  @override
  Future<Position?> getCurrentPosition() async => null;
}

class _Recorder extends Interceptor {
  _Recorder({this.uploadDelay = Duration.zero});
  final Duration uploadDelay;
  final uploads = <Uint8List>[];
  final fields = <Map<String, String>>[];
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await Future<void>.delayed(uploadDelay);
    final data = options.data;
    if (data is FormData) {
      fields.add({for (final f in data.fields) f.key: f.value});
      for (final file in data.files) {
        final builder = BytesBuilder();
        await for (final chunk in file.value.finalize()) {
          builder.add(chunk);
        }
        uploads.add(builder.toBytes());
      }
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'success': true},
      ),
    );
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('imagery_screen_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<_Recorder> pumpScreen(
    WidgetTester tester,
    String pickedPath, {
    Duration pickDelay = Duration.zero,
    Duration uploadDelay = Duration.zero,
  }) async {
    final recorder = _Recorder(uploadDelay: uploadDelay);
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))
      ..interceptors.add(recorder);
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(dio: dio, allowUnauthenticatedRequests: true),
          ),
          locationServiceProvider.overrideWithValue(_NoPositionLocation()),
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(
              const AppPreferences(
                consent: ConsentSettings(imageryUpload: true),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImageryUploadScreen(
            pickImagePath: (source) async {
              await Future<void>.delayed(pickDelay);
              return pickedPath;
            },
            sanitizedDirectory: dir,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return recorder;
  }

  // The mounted callbacks return the whole production operation's Future even
  // though Flutter exposes them as void callbacks. Await it in the real async
  // zone so file I/O and multipart consumption complete before any assertion.
  Future<void> pick(WidgetTester tester, String label) async {
    final picker = tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.text('Tap to take photo or select from gallery'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.runAsync(() async {
      final operation = Function.apply(picker.onTap!, const []) as Future<void>;
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await operation.timeout(const Duration(seconds: 10));
    });
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Submit for validation'));
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submit for validation'),
    );
    expect(button.onPressed, isNotNull);
    await tester.runAsync(() async {
      final operation =
          Function.apply(button.onPressed!, const []) as Future<void>;
      await operation.timeout(const Duration(seconds: 10));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'selection delayed beyond the old observation budget still uploads sanitized bytes',
    (tester) async {
      final original = pngWith([zTxtChunk(gpsText)]);
      final picked = File('${dir.path}/delayed.png')
        ..writeAsBytesSync(original);
      final recorder = await pumpScreen(
        tester,
        picked.path,
        pickDelay: const Duration(seconds: 3),
      );
      await pick(tester, 'Gallery');
      await submit(tester);
      expect(recorder.uploads, hasLength(1));
      expect(recoversText(recorder.uploads.single, 'GPSLatitude'), isFalse);
    },
  );

  testWidgets(
    'multipart consumption delayed beyond the old budget completes before assertions',
    (tester) async {
      final original = pngWith([iccpChunk(gpsText)]);
      final picked = File('${dir.path}/delayed-upload.png')
        ..writeAsBytesSync(original);
      final recorder = await pumpScreen(
        tester,
        picked.path,
        uploadDelay: const Duration(seconds: 2),
      );
      await pick(tester, 'Gallery');
      await submit(tester);
      expect(recorder.uploads, hasLength(1));
      expect(recoversText(recorder.uploads.single, 'GPSLatitude'), isFalse);
      expect(pngChunkTypes(recorder.uploads.single), ['IHDR', 'IDAT', 'IEND']);
    },
  );

  for (final (source, label) in [
    ('camera', 'Camera'),
    ('gallery', 'Gallery'),
  ]) {
    testWidgets(
      '$source photo with GPS EXIF: the uploaded bytes carry no GPS and keep the orientation',
      (tester) async {
        final original = gpsJpeg();
        final picked = File('${dir.path}/$source.jpg')
          ..writeAsBytesSync(original);
        expect(
          gpsFromJpeg(original),
          isNotNull,
        ); // control: the picked file really carries it
        final recorder = await pumpScreen(tester, picked.path);
        await pick(tester, label);
        await submit(tester);
        expect(recorder.uploads, hasLength(1));
        final sent = recorder.uploads.single;
        expect(gpsFromJpeg(sent), isNull);
        expect(orientationOf(sent), 6);
        expect(String.fromCharCodes(sent).contains('10.123'), isFalse);
        expect(String.fromCharCodes(sent).contains('TRAILER'), isFalse);
      },
    );
  }

  // mobile#375 P1: location text hidden in metadata the sanitizer keeps or copies is caught by an
  // allowlist. Each case goes through the real screen, the sanitizer service, the app-owned copy and the
  // multipart upload, and the captured bytes are read independently (markers, chunks, zlib, ICC tags).
  final hidden = <String, (String, Uint8List)>{
    'JPEG with an ICC profile whose description is GPS text': (
      'icc.jpg',
      jpegWith([iccApp2(gpsText)]),
    ),
    'JPEG with APP13 and APP15 payloads': (
      'app.jpg',
      jpegWith([app13(gpsText), app15(gpsText)]),
    ),
    'PNG with a compressed iCCP profile': (
      'icc.png',
      pngWith([iccpChunk(gpsText)]),
    ),
    'PNG with an unknown ancillary chunk': (
      'unk.png',
      pngWith([unknownChunk(gpsText)]),
    ),
    'PNG with a zTXt chunk': ('z.png', pngWith([zTxtChunk(gpsText)])),
  };
  for (final entry in hidden.entries) {
    testWidgets('real upload: ${entry.key} leaves no recoverable location', (
      tester,
    ) async {
      final (name, original) = entry.value;
      final picked = File('${dir.path}/$name')..writeAsBytesSync(original);
      expect(
        recoversText(original, gpsText),
        isTrue,
        reason: 'control: the picked file really carries the text',
      );
      final recorder = await pumpScreen(tester, picked.path);
      await pick(tester, 'Gallery');
      await submit(tester);
      expect(recorder.uploads, hasLength(1));
      final sent = recorder.uploads.single;
      expect(recoversText(sent, 'GPSLatitude'), isFalse);
      expect(recoversText(sent, '10.123'), isFalse);
      if (name.endsWith('.png')) {
        expect(pngChunkTypes(sent), ['IHDR', 'IDAT', 'IEND']);
        // The uploaded PNG still decodes (independent of the sanitizer) to the same 1x1 picture.
        final frame = await tester.runAsync(
          () async => (await (await ui.instantiateImageCodec(
            sent,
          )).getNextFrame()).image,
        );
        expect(frame!.width, 1);
        expect(frame.height, 1);
      } else {
        expect(jpegMarkers(sent).where((m) => m >= 0xE1 && m <= 0xEF), isEmpty);
        expect(jpegMarkers(sent), isNot(contains(0xE2)));
      }
    });
  }

  // mobile#375 round 3: a retained chunk or segment must be exactly its specified structure, so
  // location text in excess tRNS bytes, IEND bytes or JPEG slack cannot ride along. The file is
  // refused (no selection, no upload), never passed on with the text inside.
  final malformed = <String, (String, Uint8List)>{
    'PNG with location text in an excess tRNS': (
      'trns.png',
      pngWith([('tRNS', gpsText.codeUnits)]),
    ),
    'PNG with location text in IEND bytes': (
      'iend.png',
      pngWith(const [], iendPayload: gpsText.codeUnits),
    ),
    'JPEG with location text in DQT slack': (
      'dqt.jpg',
      jpegWith(const [], dqtSlack: gpsText.codeUnits),
    ),
    'JPEG with location text in SOS header slack': (
      'sos.jpg',
      jpegWith(const [], sosSlack: gpsText.codeUnits),
    ),
  };
  for (final entry in malformed.entries) {
    testWidgets(
      'real upload: ${entry.key} is refused and nothing is uploaded',
      (tester) async {
        final (name, original) = entry.value;
        final picked = File('${dir.path}/$name')..writeAsBytesSync(original);
        expect(
          recoversText(original, gpsText),
          isTrue,
          reason: 'control: the picked file really carries the text',
        );
        final recorder = await pumpScreen(tester, picked.path);
        await pick(tester, 'Gallery');
        final button = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Submit for validation'),
        );
        expect(button.onPressed, isNull); // no photo selected
        expect(recorder.uploads, isEmpty);
        expect(
          dir.listSync().whereType<File>().where(
            (f) => f.uri.pathSegments.last.startsWith('imagery_'),
          ),
          isEmpty,
        );
      },
    );
  }

  testWidgets(
    'a photo that cannot be sanitized is refused and nothing is uploaded',
    (tester) async {
      final picked = File('${dir.path}/odd.webp')
        ..writeAsBytesSync('RIFFxxxxWEBPVP8 '.codeUnits);
      final recorder = await pumpScreen(tester, picked.path);
      await pick(tester, 'Gallery');
      expect(find.text('Submit for validation'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit for validation'),
      );
      expect(
        button.onPressed,
        isNull,
      ); // no photo selected, so nothing to submit
      expect(recorder.uploads, isEmpty);
      expect(
        dir.listSync().whereType<File>().where(
          (f) => f.uri.pathSegments.last.startsWith('imagery_'),
        ),
        isEmpty,
      );
    },
  );
}
