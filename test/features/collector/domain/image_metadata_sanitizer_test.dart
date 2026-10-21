import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/imagery_sanitizer_service.dart';
import 'package:wrfcoin_mobile/features/collector/domain/image_metadata_sanitizer.dart';

import '../../../test_helpers/gps_jpeg.dart';
import '../../../test_helpers/metadata_fixtures.dart';

bool _contains(Uint8List bytes, String needle) => String.fromCharCodes(bytes).contains(needle);

void main() {
  group('the fixture really carries the position (control)', () {
    test('an independent EXIF reader recovers it from the original JPEG', () {
      final gps = gpsFromJpeg(gpsJpeg());
      expect(gps, isNotNull);
      expect(gps!.lat, closeTo(10.123, 0.0001));
      expect(gps.lon, closeTo(20.456, 0.0001));
    });
  });

  group('JPEG', () {
    final clean = sanitizeImageMetadata(gpsJpeg());

    test('no GPS survives: EXIF GPS, XMP, IPTC, comment and trailer are gone', () {
      expect(gpsFromJpeg(clean), isNull);
      for (final needle in ['10.123', '20.456', 'xap', 'Photoshop', 'TRAILER', 'taken at']) {
        expect(_contains(clean, needle), isFalse, reason: needle);
      }
    });

    test('orientation is preserved through a minimal EXIF that holds nothing else', () {
      expect(orientationOf(clean), 6);
    });

    test('orientation 1 (upright) needs no EXIF segment at all', () {
      final upright = sanitizeImageMetadata(gpsJpeg(orientation: 1));
      expect(orientationOf(upright), isNull);
      expect(gpsFromJpeg(upright), isNull);
    });

    test('still a well-formed JPEG: SOI ... EOI, JFIF kept, the image data byte-identical', () {
      expect(clean.sublist(0, 2), [0xFF, 0xD8]);
      expect(clean.sublist(clean.length - 2), [0xFF, 0xD9]);
      expect(_contains(clean, 'JFIF'), isTrue);
      final hex = clean.toList();
      final at = _indexOf(hex, entropyData);
      expect(at, greaterThan(0));
      expect(hex.sublist(at, at + entropyData.length), entropyData);
    });

    test('an already clean JPEG is left equivalent (idempotent)', () {
      expect(sanitizeImageMetadata(clean), clean);
    });

    test('truncated or garbage input fails closed', () {
      final original = gpsJpeg();
      expect(() => sanitizeImageMetadata(Uint8List.sublistView(original, 0, 40)), throwsA(isA<ImageSanitizeException>()));
      expect(() => sanitizeImageMetadata(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00, 0x01])), throwsA(isA<ImageSanitizeException>()));
    });
  });

  group('PNG and other formats', () {
    test('PNG loses eXIf and text chunks and anything after IEND', () {
      final clean = sanitizeImageMetadata(gpsPng());
      for (final needle in ['eXIf', 'tEXt', '10.123', 'TRAILER']) {
        expect(_contains(clean, needle), isFalse, reason: needle);
      }
      expect(_contains(clean, 'IDAT'), isTrue);
      expect(_contains(clean, 'IEND'), isTrue);
    });

    test('an unsupported format is refused, not passed through', () {
      expect(() => sanitizeImageMetadata(Uint8List.fromList('RIFFxxxxWEBPVP8 '.codeUnits)), throwsA(isA<ImageSanitizeException>()));
      expect(() => sanitizeImageMetadata(Uint8List(0)), throwsA(isA<ImageSanitizeException>()));
    });
  });

  group('sanitizePickedImage writes an app-owned clean copy', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('imagery_'));
    tearDown(() => dir.deleteSync(recursive: true));

    for (final source in ['camera', 'gallery']) {
      test('$source photo with GPS: the copy has none and is a different file', () async {
        final picked = File('${dir.path}/$source.jpg')..writeAsBytesSync(gpsJpeg());
        final out = await sanitizePickedImage(picked.path, into: dir);
        expect(out.path, isNot(picked.path));
        final bytes = out.readAsBytesSync();
        expect(gpsFromJpeg(bytes), isNull);
        expect(orientationOf(bytes), 6);
      });
    }

    test('a photo that cannot be sanitized throws and leaves no output file', () async {
      final picked = File('${dir.path}/bad.webp')..writeAsBytesSync('RIFFxxxxWEBPVP8 '.codeUnits);
      await expectLater(sanitizePickedImage(picked.path, into: dir), throwsA(isA<ImageSanitizeException>()));
      expect(dir.listSync().whereType<File>().where((f) => f.uri.pathSegments.last.startsWith('imagery_')), isEmpty);
    });
  });

  group('allowlist: metadata hidden in retained containers (mobile#375 P1)', () {
    test('controls: the fixtures really carry the text (independent ICC, zlib and marker readers)', () {
      expect(iccDescription(iccProfileWithDescription(gpsText)), gpsText);
      final icc = jpegWith([iccApp2(gpsText)]);
      expect(jpegMarkers(icc), contains(0xE2));
      expect(recoversText(icc, gpsText), isTrue);
      final png = pngWith([iccpChunk(gpsText), zTxtChunk(gpsText), unknownChunk(gpsText)]);
      expect(pngChunkTypes(png), containsAll(['iCCP', 'zTXt', 'gpSm']));
      // The compressed copies are invisible to a raw grep but recovered by inflating.
      expect(_contains(pngWith([iccpChunk(gpsText)]), 'GPSLatitude'), isFalse);
      expect(recoversText(pngWith([iccpChunk(gpsText)]), gpsText), isTrue);
      expect(recoversText(pngWith([zTxtChunk(gpsText)]), gpsText), isTrue);
    });

    test('JPEG: an ICC profile whose description carries GPS text is dropped', () {
      final clean = sanitizeImageMetadata(jpegWith([iccApp2(gpsText)]));
      expect(jpegMarkers(clean), isNot(contains(0xE2)));
      expect(recoversText(clean, 'GPSLatitude'), isFalse);
      expect(recoversText(clean, '10.123'), isFalse);
    });

    test('JPEG: APP13 (IPTC/Photoshop) and APP15 payloads are dropped, with every other APPn and COM', () {
      final clean = sanitizeImageMetadata(jpegWith([
        app13(gpsText),
        app15(gpsText),
        _seg(0xE5, gpsText.codeUnits),
        _seg(0xEC, gpsText.codeUnits),
        _seg(0xFE, gpsText.codeUnits),
      ]));
      expect(jpegMarkers(clean).where((m) => (m >= 0xE1 && m <= 0xEF) || m == 0xFE), isEmpty);
      expect(recoversText(clean, 'GPSLatitude'), isFalse);
    });

    test('JPEG: the JFIF thumbnail and any bytes after it are not kept; the header is the fixed 16 bytes', () {
      final clean = sanitizeImageMetadata(jpegWith(const [], jfifPayload: jfifWithThumbnail(gpsText)));
      expect(recoversText(clean, 'GPSLatitude'), isFalse);
      expect(clean.sublist(2, 20), [0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 1, 2, 1, 0, 72, 0, 72, 0, 0]);
    });

    test('JPEG: Adobe APP14 is kept only as its fixed fields (CMYK/YCCK transform), text after them is gone', () {
      final clean = sanitizeImageMetadata(jpegWith([adobeApp14(transform: 2, trailingText: gpsText)]));
      final at = _indexOf(clean.toList(), 'Adobe'.codeUnits);
      expect(at, greaterThan(0));
      expect(clean.sublist(at - 4, at + 12), [0xFF, 0xEE, 0x00, 0x0E, ...'Adobe'.codeUnits, 0x00, 0x64, 0, 0, 0, 0, 2]);
      expect(recoversText(clean, 'GPSLatitude'), isFalse);
      // an Adobe segment with an unknown transform is dropped outright
      expect(_contains(sanitizeImageMetadata(jpegWith([adobeApp14(transform: 9)])), 'Adobe'), isFalse);
    });

    test('JPEG: what remains is exactly the allowlist (and the image data is byte-identical)', () {
      final clean = sanitizeImageMetadata(jpegWith([iccApp2(gpsText), app13(gpsText), app15(gpsText), adobeApp14()]));
      const allowed = {0xD8, 0xE0, 0xEE, 0xDB, 0xC0, 0xDA, 0xD9};
      expect(jpegMarkers(clean).toSet().difference(allowed), isEmpty);
      final at = _indexOf(clean.toList(), [0x12, 0x34, 0xFF, 0x00, 0x56, 0x78]);
      expect(at, greaterThan(0));
    });

    test('PNG: iCCP with a compressed GPS profile description is dropped', () {
      final clean = sanitizeImageMetadata(pngWith([iccpChunk(gpsText)]));
      expect(pngChunkTypes(clean), isNot(contains('iCCP')));
      expect(recoversText(clean, 'GPSLatitude'), isFalse);
    });

    test('PNG: an unknown ancillary chunk, a zTXt and a private chunk are dropped', () {
      final clean = sanitizeImageMetadata(pngWith([unknownChunk(gpsText), zTxtChunk(gpsText), ('prVt', gpsText.codeUnits), ('pHYs', [0, 0, 0x0B, 0x13, 0, 0, 0x0B, 0x13, 1])]));
      expect(pngChunkTypes(clean), ['IHDR', 'IDAT', 'IEND']);
      expect(recoversText(clean, 'GPSLatitude'), isFalse);
    });

    test('PNG: the rendering chunks stay, in order, with validated structure only', () {
      final clean = sanitizeImageMetadata(pngWith([
        ('gAMA', [0, 1, 0x86, 0xA0]),
        ('cHRM', List.filled(32, 1)),
        ('sRGB', [0]),
        ('sBIT', [8, 8, 8]),
        ('PLTE', [1, 2, 3]),
        ('tRNS', [0, 0, 0, 0, 0, 0]),
      ]));
      expect(pngChunkTypes(clean), ['IHDR', 'gAMA', 'cHRM', 'sRGB', 'sBIT', 'PLTE', 'tRNS', 'IDAT', 'IEND']);
    });

    test('PNG: a fixed-size ancillary chunk with the wrong length (a place to hide text) is dropped', () {
      final clean = sanitizeImageMetadata(pngWith([
        ('gAMA', gpsText.codeUnits),
        ('cHRM', gpsText.codeUnits),
        ('sRGB', gpsText.codeUnits),
        ('sBIT', gpsText.codeUnits),
      ]));
      expect(pngChunkTypes(clean), ['IHDR', 'IDAT', 'IEND']);
    });

    test('PNG: a repeated ancillary rendering chunk, or one after the image data, is dropped', () {
      final clean = sanitizeImageMetadata(pngWith([
        ('gAMA', [0, 1, 0x86, 0xA0]),
        ('gAMA', gpsText.codeUnits.sublist(0, 4)),
        ('sRGB', [0]),
        ('sRGB', [1]),
      ]));
      expect(pngChunkTypes(clean), ['IHDR', 'gAMA', 'sRGB', 'IDAT', 'IEND']);
    });

    final excess = gpsText.codeUnits;
    for (final (label, extra, colorType) in [
      ('tRNS excess for truecolour (needs exactly 6 bytes)', [('tRNS', excess)], 2),
      ('tRNS excess for greyscale (needs exactly 2 bytes)', [('tRNS', excess)], 0),
      ('tRNS for greyscale+alpha (forbidden)', [('tRNS', [0, 0])], 4),
      ('tRNS for truecolour+alpha (forbidden)', [('tRNS', [0, 0, 0, 0, 0, 0])], 6),
      ('tRNS longer than the palette', [('PLTE', [1, 2, 3, 4, 5, 6]), ('tRNS', [1, 2, 3])], 3),
      ('tRNS for a palette image with no PLTE', [('tRNS', [1])], 3),
      ('PLTE for greyscale (forbidden)', [('PLTE', [1, 2, 3])], 0),
      ('PLTE not a multiple of 3', [('PLTE', [1, 2, 3, 4])], 2),
      ('a repeated PLTE', [('PLTE', [1, 2, 3]), ('PLTE', [1, 2, 3])], 2),
      ('a repeated tRNS', [('tRNS', [0, 0, 0, 0, 0, 0]), ('tRNS', [0, 0, 0, 0, 0, 0])], 2),
    ]) {
      test('PNG malformed critical chunk is refused, not passed on: $label', () {
        expect(() => sanitizeImageMetadata(pngWith(extra, colorType: colorType)), throwsA(isA<ImageSanitizeException>()));
      });
    }

    test('PNG: the exact tRNS sizes per colour type are kept', () {
      expect(pngChunkTypes(sanitizeImageMetadata(pngWith([('tRNS', [0, 0])], colorType: 0))), contains('tRNS'));
      expect(pngChunkTypes(sanitizeImageMetadata(pngWith([('tRNS', [0, 0, 0, 0, 0, 0])], colorType: 2))), contains('tRNS'));
      expect(pngChunkTypes(sanitizeImageMetadata(pngWith([('PLTE', [1, 2, 3, 4, 5, 6]), ('tRNS', [9, 9])], colorType: 3))), ['IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND']);
    });

    test('PNG: IEND that carries bytes (text after the marker chunk) is refused', () {
      expect(() => sanitizeImageMetadata(pngWith(const [], iendPayload: excess)), throwsA(isA<ImageSanitizeException>()));
    });

    test('PNG: an IHDR with invalid fields is refused', () {
      expect(() => sanitizeImageMetadata(pngWith(const [], colorType: 2, bitDepth: 4)), throwsA(isA<ImageSanitizeException>()));
    });

    test('JPEG: slack bytes carrying text inside a kept segment are refused (DQT, SOF, SOS, DRI)', () {
      for (final bad in [
        jpegWith(const [], dqtSlack: excess),
        jpegWith(const [], sofSlack: excess),
        jpegWith(const [], sosSlack: excess),
        jpegWith(const [], driPayload: [0, 10, ...excess]),
      ]) {
        expect(() => sanitizeImageMetadata(bad), throwsA(isA<ImageSanitizeException>()));
      }
      // control: the same segments with exact structure pass
      expect(() => sanitizeImageMetadata(jpegWith(const [], driPayload: [0, 10])), returnsNormally);
    });

    test('PNG: sBIT length must match the colour type (palette 3, gray+alpha 2)', () {
      expect(pngChunkTypes(sanitizeImageMetadata(pngWith([('sBIT', [8, 8])], colorType: 4))), contains('sBIT'));
      expect(pngChunkTypes(sanitizeImageMetadata(pngWith([('sBIT', [8, 8])], colorType: 2))), isNot(contains('sBIT')));
    });

    test('PNG: a file that does not start with IHDR fails closed', () {
      final bad = BytesBuilder()
        ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add([0, 0, 0, 0, ...'IDAT'.codeUnits, 0, 0, 0, 0])
        ..add([0, 0, 0, 0, ...'IEND'.codeUnits, 0, 0, 0, 0]);
      expect(() => sanitizeImageMetadata(bad.toBytes()), throwsA(isA<ImageSanitizeException>()));
    });
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var k = 0; k < needle.length; k++) {
      if (haystack[i + k] != needle[k]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;

}

List<int> _seg(int marker, List<int> payload) => [0xFF, marker, (payload.length + 2) >> 8, (payload.length + 2) & 0xFF, ...payload];
