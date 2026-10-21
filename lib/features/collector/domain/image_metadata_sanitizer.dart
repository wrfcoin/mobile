import 'dart:typed_data';

/// Thrown when an image cannot be proven free of location metadata. The caller must not upload.
class ImageSanitizeException implements Exception {
  const ImageSanitizeException(this.message);
  final String message;
  @override
  String toString() => 'ImageSanitizeException: $message';
}

/// Returns [input] with only what is needed to show the picture, in pure Dart (no decoding or
/// re-encoding of pixels, so the image data itself is byte-identical). This is an ALLOWLIST: anything
/// not named below is dropped, so a location string hidden in a free-form field cannot survive.
///
/// JPEG keeps: SOI, a rebuilt fixed 16-byte JFIF APP0 (no embedded thumbnail), a minimal EXIF APP1 that
/// carries ONLY the orientation tag, a rebuilt fixed 12-byte Adobe APP14 (only when its transform byte is
/// 0, 1 or 2, which CMYK/YCCK decoding needs), the coding segments (DQT, DHT, DAC, SOFn, DRI, DNL, SOS)
/// with their entropy-coded data, and EOI. Dropped: ICC profile APP2 (its description and other tags are
/// free text), EXIF/XMP (APP1), IPTC/Photoshop (APP13), MPF, every other APPn, comments (COM) and
/// anything after EOI.
///
/// PNG keeps: IHDR, PLTE, tRNS, IDAT, IEND and the fixed-size gAMA (4 bytes), cHRM (32), sRGB (1) and
/// sBIT (by colour type) chunks, each with a validated length. Dropped: iCCP (a compressed profile),
/// eXIf, every text chunk (tEXt, zTXt, iTXt), tIME, pHYs and every unknown or private chunk, and anything
/// after IEND.
///
/// Any other format, or a file that does not parse, throws [ImageSanitizeException] (fail closed).
Uint8List sanitizeImageMetadata(Uint8List input) {
  if (input.length >= 3 && input[0] == 0xFF && input[1] == 0xD8 && input[2] == 0xFF) {
    return _sanitizeJpeg(input);
  }
  if (input.length >= 8 &&
      input[0] == 0x89 && input[1] == 0x50 && input[2] == 0x4E && input[3] == 0x47 &&
      input[4] == 0x0D && input[5] == 0x0A && input[6] == 0x1A && input[7] == 0x0A) {
    return _sanitizePng(input);
  }
  throw const ImageSanitizeException('Only JPEG and PNG photos can be uploaded.');
}

Uint8List _sanitizeJpeg(Uint8List data) {
  final out = BytesBuilder(copy: false);
  out.add(const [0xFF, 0xD8]);
  int? orientation;
  Uint8List? jfif;
  Uint8List? adobe;
  final kept = BytesBuilder(copy: false);
  var i = 2;
  var sawImageData = false;
  var ended = false;

  Never fail(String why) => throw ImageSanitizeException('JPEG not understood: $why');

  while (i < data.length) {
    if (data[i] != 0xFF) fail('expected a marker at $i');
    while (i < data.length && data[i] == 0xFF) {
      i++; // fill bytes
    }
    if (i >= data.length) fail('truncated marker');
    final marker = data[i++];
    if (marker == 0xD9) {
      ended = true;
      break;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0xD8) continue;
    if (i + 2 > data.length) fail('truncated length');
    final length = (data[i] << 8) | data[i + 1];
    if (length < 2 || i + length > data.length) fail('bad segment length');
    final payload = Uint8List.sublistView(data, i + 2, i + length);
    final whole = Uint8List.sublistView(data, i - 2, i + length); // FF marker + length + payload
    i += length;

    if (marker == 0xE1 && _startsWith(payload, const [0x45, 0x78, 0x69, 0x66, 0x00, 0x00])) {
      orientation ??= _exifOrientation(payload, 6);
      continue; // EXIF dropped
    }
    if (marker == 0xE0 && _startsWith(payload, const [0x4A, 0x46, 0x49, 0x46, 0x00])) {
      // JFIF: rebuilt with the 9 fixed fields and NO thumbnail.
      if (payload.length >= 14 && jfif == null) jfif = _rebuiltJfif(payload);
      continue;
    }
    if (marker == 0xEE && _startsWith(payload, const [0x41, 0x64, 0x6F, 0x62, 0x65])) {
      // Adobe APP14: only the fixed colour-transform fields, rebuilt.
      if (payload.length >= 12 && payload[11] <= 2 && adobe == null) adobe = _rebuiltAdobe(payload[11]);
      continue;
    }
    // Allowlist: only the coding segments stay (DQT, DHT, DAC, SOFn, DRI, DNL, SOS). Every APPn
    // (ICC profile, XMP, IPTC, MPF, vendor data), every comment and every other marker is dropped.
    if (!_isCodingMarker(marker)) continue;
    // A kept segment must be exactly its specified structure: no slack bytes can carry data.
    if (!_codingSegmentIsExact(marker, payload)) fail('malformed segment 0x${marker.toRadixString(16)}');

    // A coding segment (tables, frame, scan header) stays as it is.
    kept.add(whole);
    if (marker == 0xDA) {
      // Scan header: copy the entropy-coded data up to the next real marker.
      sawImageData = true;
      final start = i;
      while (i < data.length) {
        if (data[i] == 0xFF) {
          final next = i + 1 < data.length ? data[i + 1] : -1;
          if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
            i += 2;
            continue;
          }
          if (next == 0xFF) {
            i++;
            continue;
          }
          break; // a real marker
        }
        i++;
      }
      if (i >= data.length) fail('truncated image data');
      kept.add(Uint8List.sublistView(data, start, i));
    }
  }
  if (!ended || !sawImageData) fail('no image data or no end marker');

  // Rebuild: SOI, [JFIF], [minimal EXIF with orientation], [Adobe], coding segments, EOI.
  if (jfif != null) out.add(jfif);
  if (orientation != null && orientation >= 1 && orientation <= 8 && orientation != 1) {
    out.add(_minimalExif(orientation));
  }
  if (adobe != null) out.add(adobe);
  out.add(kept.takeBytes());
  out.add(const [0xFF, 0xD9]);
  return out.takeBytes();
}

/// Whether [payload] is EXACTLY the structure JPEG defines for [marker] (length-bounded, no slack).
bool _codingSegmentIsExact(int marker, Uint8List p) {
  switch (marker) {
    case 0xDD: // DRI: restart interval
      return p.length == 2;
    case 0xDC: // DNL: number of lines
      return p.length == 2;
    case 0xDA: // SOS: Ns, Ns * (selector, tables), Ss, Se, Ah/Al
      if (p.isEmpty) return false;
      return p.length == 1 + 2 * p[0] + 3 && p[0] >= 1 && p[0] <= 4;
    case 0xDB: // DQT: repeated (Pq/Tq, 64 * (Pq ? 2 : 1) bytes)
      var i = 0;
      while (i < p.length) {
        final precision = p[i] >> 4;
        if (precision > 1) return false;
        i += 1 + 64 * (precision == 1 ? 2 : 1);
      }
      return p.isNotEmpty && i == p.length;
    case 0xC4: // DHT: repeated (Tc/Th, 16 code counts, symbols)
      var j = 0;
      while (j < p.length) {
        if (j + 17 > p.length) return false;
        var symbols = 0;
        for (var k = 1; k <= 16; k++) {
          symbols += p[j + k];
        }
        j += 17 + symbols;
      }
      return p.isNotEmpty && j == p.length;
    case 0xCC: // DAC: repeated (Tc/Tb, value)
      return p.isNotEmpty && p.length % 2 == 0;
    default: // SOFn: P, Y(2), X(2), Nf, Nf * (C, H/V, Tq)
      if (p.length < 6) return false;
      return p.length == 6 + 3 * p[5] && p[5] >= 1;
  }
}

bool _isCodingMarker(int marker) =>
    marker == 0xDB || // DQT
    marker == 0xC4 || // DHT
    marker == 0xCC || // DAC
    marker == 0xDD || // DRI
    marker == 0xDC || // DNL
    marker == 0xDA || // SOS
    (marker >= 0xC0 && marker <= 0xCF && marker != 0xC8 && marker != 0xC4 && marker != 0xCC); // SOFn

/// "JFIF\0", version, units, densities and a 0x0 thumbnail: always 18 bytes with the header, no
/// free-form data. [payload] is at least 14 bytes (checked by the caller).
Uint8List _rebuiltJfif(Uint8List payload) => Uint8List.fromList([
  0xFF, 0xE0, 0x00, 0x10, // APP0, length 16
  0x4A, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
  ...payload.sublist(5, 12), // version (2), units (1), X density (2), Y density (2)
  0x00, 0x00, // thumbnail width and height: none
]);

/// "Adobe", fixed version/flags and the colour transform byte: always 14 bytes with the header.
Uint8List _rebuiltAdobe(int transform) => Uint8List.fromList([
  0xFF, 0xEE, 0x00, 0x0E,
  0x41, 0x64, 0x6F, 0x62, 0x65,
  0x00, 0x64, // version 100
  0x00, 0x00, // flags0
  0x00, 0x00, // flags1
  transform,
]);

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var k = 0; k < prefix.length; k++) {
    if (bytes[k] != prefix[k]) return false;
  }
  return true;
}

/// Orientation (1-8) from the TIFF structure of an EXIF payload, or null. Never throws.
int? _exifOrientation(Uint8List payload, int tiffStart) {
  try {
    if (payload.length < tiffStart + 8) return null;
    final little = payload[tiffStart] == 0x49 && payload[tiffStart + 1] == 0x49;
    final big = payload[tiffStart] == 0x4D && payload[tiffStart + 1] == 0x4D;
    if (!little && !big) return null;
    int u16(int o) => little ? payload[o] | (payload[o + 1] << 8) : (payload[o] << 8) | payload[o + 1];
    int u32(int o) => little
        ? payload[o] | (payload[o + 1] << 8) | (payload[o + 2] << 16) | (payload[o + 3] << 24)
        : (payload[o] << 24) | (payload[o + 1] << 16) | (payload[o + 2] << 8) | payload[o + 3];
    if (u16(tiffStart + 2) != 42) return null;
    final ifd = tiffStart + u32(tiffStart + 4);
    if (ifd + 2 > payload.length) return null;
    final count = u16(ifd);
    for (var k = 0; k < count; k++) {
      final entry = ifd + 2 + k * 12;
      if (entry + 12 > payload.length) return null;
      if (u16(entry) == 0x0112 && u16(entry + 2) == 3) {
        final value = u16(entry + 8);
        return value >= 1 && value <= 8 ? value : null;
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// An APP1 EXIF segment holding only the orientation tag (big-endian TIFF, one IFD entry).
Uint8List _minimalExif(int orientation) {
  final body = <int>[
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // TIFF header, IFD0 at 8
    0x00, 0x01, // one entry
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, orientation, 0x00, 0x00, // Orientation SHORT
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ];
  final length = body.length + 2;
  return Uint8List.fromList([0xFF, 0xE1, (length >> 8) & 0xFF, length & 0xFF, ...body]);
}

/// PNG: each retained chunk must have EXACTLY the structure the format gives it, so no excess
/// payload survives. A malformed critical chunk (IHDR, PLTE, tRNS, IEND) makes the file invalid and
/// it is refused (fail closed); a malformed, repeated or misplaced ancillary rendering chunk (gAMA,
/// cHRM, sRGB, sBIT) is dropped. Every other chunk is dropped.
Uint8List _sanitizePng(Uint8List data) {
  Never bad(String why) => throw ImageSanitizeException('PNG not understood: $why');
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(data, 0, 8));
  var i = 8;
  var sawEnd = false;
  var sawData = false;
  var first = true;
  int colorType = 0;
  int bitDepth = 8;
  int? paletteEntries;
  var sawTrns = false;
  final seenAncillary = <String>{};
  while (i < data.length) {
    if (i + 12 > data.length) bad('truncated chunk');
    final length = (data[i] << 24) | (data[i + 1] << 16) | (data[i + 2] << 8) | data[i + 3];
    final end = i + 12 + length;
    if (length < 0 || end > data.length) bad('bad chunk length');
    final type = String.fromCharCodes(data.sublist(i + 4, i + 8));
    final body = Uint8List.sublistView(data, i + 8, i + 8 + length);
    var keep = false;
    if (first) {
      if (type != 'IHDR' || length != 13) bad('no IHDR');
      first = false;
      bitDepth = body[8];
      colorType = body[9];
      const depths = {0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]};
      if (!(depths[colorType]?.contains(bitDepth) ?? false) || body[10] != 0 || body[11] != 0 || body[12] > 1) {
        bad('invalid IHDR');
      }
      keep = true;
    } else {
      switch (type) {
        case 'IHDR':
          bad('repeated IHDR');
        case 'PLTE':
          if (sawData || paletteEntries != null) bad('misplaced or repeated PLTE');
          if (colorType == 0 || colorType == 4) bad('PLTE not allowed for this colour type');
          if (length < 3 || length % 3 != 0 || length ~/ 3 > (1 << bitDepth) || length > 768) bad('invalid PLTE');
          paletteEntries = length ~/ 3;
          keep = true;
        case 'tRNS':
          if (sawData || sawTrns) bad('misplaced or repeated tRNS');
          final ok = switch (colorType) {
            0 => length == 2,
            2 => length == 6,
            3 => paletteEntries != null && length >= 1 && length <= paletteEntries,
            _ => false, // forbidden for greyscale+alpha and truecolour+alpha
          };
          if (!ok) bad('invalid tRNS');
          sawTrns = true;
          keep = true;
        case 'IDAT':
          sawData = true;
          keep = true;
        case 'IEND':
          if (length != 0) bad('IEND carries data');
          if (!sawData) bad('no image data');
          keep = true;
          sawEnd = true;
        case 'gAMA' || 'cHRM' || 'sRGB' || 'sBIT':
          // Ancillary rendering chunks: once each, before the image data, exact size.
          final size = switch (type) {
            'gAMA' => 4,
            'cHRM' => 32,
            'sRGB' => 1,
            _ => switch (colorType) { 0 => 1, 2 => 3, 3 => 3, 4 => 2, _ => 4 },
          };
          keep = !sawData && length == size && seenAncillary.add(type) && (type != 'sRGB' || body[0] <= 3);
        default:
          keep = false; // iCCP, eXIf, text chunks, tIME, pHYs and every unknown or private chunk
      }
    }
    if (keep) out.add(Uint8List.sublistView(data, i, end));
    i = end;
    if (sawEnd) break; // anything after IEND is dropped
  }
  if (!sawEnd || !sawData) bad('no image data or end');
  return out.takeBytes();
}
