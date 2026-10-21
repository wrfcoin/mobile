// Fixtures and independent readers for the metadata ALLOWLIST tests (mobile#375). The readers walk
// the bytes themselves (markers, chunks, zlib, ICC tag tables); they do not use the sanitizer.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String gpsText = 'GPSLatitude=10.123 GPSLongitude=20.456';

List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _seg(int marker, List<int> payload) => [0xFF, marker, ..._u16(payload.length + 2), ...payload];

/// A minimal valid ICC profile (header, one 'desc' tag) whose description is [text].
List<int> iccProfileWithDescription(String text) {
  final ascii = latin1.encode(text);
  final desc = [...'desc'.codeUnits, 0, 0, 0, 0, ..._u32(ascii.length + 1), ...ascii, 0, ...List.filled(79, 0)];
  const tableStart = 128;
  final dataStart = tableStart + 4 + 12;
  final total = dataStart + desc.length;
  final header = List<int>.filled(128, 0);
  header.setRange(0, 4, _u32(total));
  header.setRange(8, 12, [2, 0x10, 0, 0]);
  header.setRange(12, 16, 'mntr'.codeUnits);
  header.setRange(16, 20, 'RGB '.codeUnits);
  header.setRange(20, 24, 'XYZ '.codeUnits);
  header.setRange(36, 40, 'acsp'.codeUnits);
  return [...header, ..._u32(1), ...'desc'.codeUnits, ..._u32(dataStart), ..._u32(desc.length), ...desc];
}

const List<int> _entropy = [0x12, 0x34, 0xFF, 0x00, 0x56, 0x78];

/// A JPEG with the given extra APP segments placed before the coding segments.
Uint8List jpegWith(List<List<int>> extraSegments, {List<int>? jfifPayload, List<int> dqtSlack = const [], List<int> sofSlack = const [], List<int> sosSlack = const [], List<int>? driPayload}) {
  final b = BytesBuilder()
    ..add([0xFF, 0xD8])
    ..add(_seg(0xE0, jfifPayload ?? [0x4A, 0x46, 0x49, 0x46, 0x00, 1, 1, 0, 0, 1, 0, 1, 0, 0]));
  for (final s in extraSegments) {
    b.add(s);
  }
  if (driPayload != null) b.add(_seg(0xDD, driPayload));
  b
    ..add(_seg(0xDB, [0x00, ...List.filled(64, 8), ...dqtSlack]))
    ..add(_seg(0xC0, [8, 0, 1, 0, 1, 1, 1, 0x11, 0, ...sofSlack]))
    ..add(_seg(0xDA, [1, 1, 0, 0, 63, 0, ...sosSlack]))
    ..add(_entropy)
    ..add([0xFF, 0xD9]);
  return b.toBytes();
}

List<int> iccApp2(String text) => _seg(0xE2, ['ICC_PROFILE'.codeUnits, [0], [1, 1], iccProfileWithDescription(text)].expand((e) => e).toList());
List<int> app13(String text) => _seg(0xED, ['Photoshop 3.0'.codeUnits, [0], '8BIM'.codeUnits, [4, 4], text.codeUnits].expand((e) => e).toList());
List<int> app15(String text) => _seg(0xEF, text.codeUnits);
List<int> adobeApp14({int transform = 2, String trailingText = ''}) =>
    _seg(0xEE, ['Adobe'.codeUnits, [0, 0x65], [0x12, 0x34], [0x56, 0x78], [transform], trailingText.codeUnits].expand((e) => e).toList());

/// A JFIF payload that carries a thumbnail (2x1, three bytes per pixel) and text after it.
List<int> jfifWithThumbnail(String text) =>
    [0x4A, 0x46, 0x49, 0x46, 0x00, 1, 2, 1, 0, 72, 0, 72, 2, 1, 1, 2, 3, 4, 5, 6, ...text.codeUnits];

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}

/// A chunk with a correct CRC, so the file is a valid, decodable PNG.
List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  return [..._u32(data.length), ...body, ..._u32(_crc32(body))];
}

/// A PNG (RGB, 1x1) with [extra] chunks between IHDR and IDAT.
Uint8List pngWith(List<(String, List<int>)> extra, {int colorType = 2, int bitDepth = 8, List<int> iendPayload = const []}) {
  final b = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, bitDepth, colorType, 0, 0, 0]));
  for (final (type, data) in extra) {
    b.add(_chunk(type, data));
  }
  b
    ..add(_chunk('IDAT', zlib.encode([0, 255, 0, 0])))
    ..add(_chunk('IEND', iendPayload));
  return b.toBytes();
}

(String, List<int>) iccpChunk(String text) =>
    ('iCCP', ['icc'.codeUnits, [0, 0], zlib.encode(iccProfileWithDescription(text))].expand((e) => e).toList());
(String, List<int>) zTxtChunk(String text) =>
    ('zTXt', ['Comment'.codeUnits, [0, 0], zlib.encode(utf8.encode(text))].expand((e) => e).toList());
(String, List<int>) unknownChunk(String text) => ('gpSm', text.codeUnits);

// ---- independent readers -------------------------------------------------------------------

/// JPEG marker bytes in order up to and including EOI (walks segment lengths and entropy data).
List<int> jpegMarkers(Uint8List jpeg) {
  final out = <int>[0xD8];
  var i = 2;
  while (i + 1 < jpeg.length) {
    if (jpeg[i] != 0xFF) {
      i++;
      continue;
    }
    final m = jpeg[i + 1];
    if (m == 0x00 || m == 0xFF || (m >= 0xD0 && m <= 0xD7)) {
      i += m == 0xFF ? 1 : 2;
      continue;
    }
    out.add(m);
    if (m == 0xD9) break;
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    i += 2 + len;
  }
  return out;
}

/// PNG chunk types in order.
List<String> pngChunkTypes(Uint8List png) {
  final out = <String>[];
  var i = 8;
  while (i + 8 <= png.length) {
    final len = (png[i] << 24) | (png[i + 1] << 16) | (png[i + 2] << 8) | png[i + 3];
    out.add(String.fromCharCodes(png.sublist(i + 4, i + 8)));
    i += 12 + len;
  }
  return out;
}

/// The description text of an ICC profile (independent 'desc' tag reader), or null.
String? iccDescription(List<int> profile) {
  if (profile.length < 132 || String.fromCharCodes(profile.sublist(36, 40)) != 'acsp') return null;
  int u32(int o) => (profile[o] << 24) | (profile[o + 1] << 16) | (profile[o + 2] << 8) | profile[o + 3];
  for (var k = 0; k < u32(128); k++) {
    final e = 132 + k * 12;
    if (String.fromCharCodes(profile.sublist(e, e + 4)) == 'desc') {
      final off = u32(e + 4);
      final n = u32(off + 8);
      return String.fromCharCodes(profile.sublist(off + 12, off + 12 + n - 1));
    }
  }
  return null;
}

/// Every place [needle] could be recovered from [bytes]: raw, inside any zlib stream that inflates,
/// and inside any ICC description found in an APP2 segment or iCCP chunk.
bool recoversText(Uint8List bytes, String needle) {
  if (latin1.decode(bytes, allowInvalid: true).contains(needle)) return true;
  for (var i = 0; i + 2 < bytes.length; i++) {
    if (bytes[i] == 0x78 && (bytes[i + 1] == 0x9C || bytes[i + 1] == 0x01 || bytes[i + 1] == 0xDA || bytes[i + 1] == 0x5E)) {
      try {
        final inflated = zlib.decode(bytes.sublist(i));
        final text = latin1.decode(inflated, allowInvalid: true);
        if (text.contains(needle) || (iccDescription(inflated) ?? '').contains(needle)) return true;
      } catch (_) {
        // not a zlib stream
      }
    }
  }
  return false;
}
