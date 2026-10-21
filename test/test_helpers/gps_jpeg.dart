// Synthetic JPEG/PNG builders and an independent EXIF GPS reader for the imagery privacy tests.
// The pixel data is not a decodable picture; the sanitizer never decodes, only walks segments.
import 'dart:typed_data';

const List<int> entropyData = [0x12, 0x34, 0xFF, 0x00, 0x56, 0x78];

Uint8List _u16be(int v) => Uint8List.fromList([(v >> 8) & 0xFF, v & 0xFF]);

List<int> _le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> _rationals(double degreesValue) {
  final abs = degreesValue.abs();
  final d = abs.floor();
  final m = ((abs - d) * 60).floor();
  final s = ((abs - d) * 60 - m) * 60;
  final out = <int>[];
  for (final (n, den) in [(d, 1), (m, 1), ((s * 10000).round(), 10000)]) {
    out..addAll(_le32(n))..addAll(_le32(den));
  }
  return out;
}

/// EXIF APP1 payload (little endian): Orientation + a GPS IFD with [lat]/[lon].
List<int> exifWithGps({required double lat, required double lon, int orientation = 6}) {
  final tiff = <int>[0x49, 0x49, 0x2A, 0x00, ..._le32(8)];
  // IFD0: 2 entries, GPS IFD at 38.
  tiff
    ..addAll(_le16(2))
    ..addAll([..._le16(0x0112), ..._le16(3), ..._le32(1), ..._le16(orientation), 0, 0])
    ..addAll([..._le16(0x8825), ..._le16(4), ..._le32(1), ..._le32(38)])
    ..addAll(_le32(0));
  const gpsIfd = 38;
  const dataStart = gpsIfd + 2 + 4 * 12 + 4; // 92
  tiff
    ..addAll(_le16(4))
    ..addAll([..._le16(1), ..._le16(2), ..._le32(2), lat >= 0 ? 0x4E : 0x53, 0, 0, 0])
    ..addAll([..._le16(2), ..._le16(5), ..._le32(3), ..._le32(dataStart)])
    ..addAll([..._le16(3), ..._le16(2), ..._le32(2), lon >= 0 ? 0x45 : 0x57, 0, 0, 0])
    ..addAll([..._le16(4), ..._le16(5), ..._le32(3), ..._le32(dataStart + 24)])
    ..addAll(_le32(0))
    ..addAll(_rationals(lat))
    ..addAll(_rationals(lon));
  return [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, ...tiff];
}

List<int> _segment(int marker, List<int> payload) => [0xFF, marker, ..._u16be(payload.length + 2), ...payload];

/// A JPEG that carries GPS in EXIF, plus XMP, IPTC, a comment, JFIF, a trailer after EOI.
Uint8List gpsJpeg({double lat = 10.123, double lon = 20.456, int orientation = 6, bool trailer = true}) {
  final b = BytesBuilder()
    ..add([0xFF, 0xD8])
    ..add(_segment(0xE0, [0x4A, 0x46, 0x49, 0x46, 0x00, 1, 1, 0, 0, 1, 0, 1, 0, 0]))
    ..add(_segment(0xE1, exifWithGps(lat: lat, lon: lon, orientation: orientation)))
    ..add(_segment(0xE1, 'http://ns.adobe.com/xap/1.0/\x00<x:gps lat="$lat" lon="$lon"/>'.codeUnits))
    ..add(_segment(0xED, 'Photoshop 3.0\x00gps $lat $lon'.codeUnits))
    ..add(_segment(0xFE, 'taken at $lat,$lon'.codeUnits))
    ..add(_segment(0xDB, [0x00, ...List.filled(64, 8)]))
    ..add(_segment(0xC0, [8, 0, 1, 0, 1, 1, 1, 0x11, 0]))
    ..add(_segment(0xDA, [1, 1, 0, 0, 63, 0]))
    ..add(entropyData)
    ..add([0xFF, 0xD9]);
  if (trailer) b.add('TRAILER-GPS $lat,$lon'.codeUnits);
  return b.toBytes();
}

/// EXIF GPS (lat, lon) recovered from any EXIF APP1 segment of [jpeg], or null when none.
({double lat, double lon})? gpsFromJpeg(Uint8List jpeg) {
  var i = 2;
  while (i + 4 <= jpeg.length && jpeg[i] == 0xFF) {
    final marker = jpeg[i + 1];
    if (marker == 0xDA || marker == 0xD9) break;
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (marker == 0xE1 && len > 10 && String.fromCharCodes(jpeg.sublist(i + 4, i + 8)) == 'Exif') {
      final r = _gpsFromExif(Uint8List.sublistView(jpeg, i + 10, i + 2 + len));
      if (r != null) return r;
    }
    i += 2 + len;
  }
  return null;
}

({double lat, double lon})? _gpsFromExif(Uint8List t) {
  final big = t[0] == 0x4D;
  int u16(int o) => big ? (t[o] << 8) | t[o + 1] : t[o] | (t[o + 1] << 8);
  int u32(int o) => big
      ? (t[o] << 24) | (t[o + 1] << 16) | (t[o + 2] << 8) | t[o + 3]
      : t[o] | (t[o + 1] << 8) | (t[o + 2] << 16) | (t[o + 3] << 24);
  double deg(int o) {
    double r(int k) => u32(o + k * 8) / u32(o + k * 8 + 4);
    return r(0) + r(1) / 60 + r(2) / 3600;
  }
  final ifd0 = u32(4);
  int? gps;
  for (var k = 0; k < u16(ifd0); k++) {
    final e = ifd0 + 2 + k * 12;
    if (u16(e) == 0x8825) gps = u32(e + 8);
  }
  if (gps == null) return null;
  double? lat, lon;
  for (var k = 0; k < u16(gps); k++) {
    final e = gps + 2 + k * 12;
    if (u16(e) == 2) lat = deg(u32(e + 8));
    if (u16(e) == 4) lon = deg(u32(e + 8));
  }
  return lat == null || lon == null ? null : (lat: lat, lon: lon);
}

/// The Orientation value from the first EXIF segment, or null.
int? orientationOf(Uint8List jpeg) {
  var i = 2;
  while (i + 4 <= jpeg.length && jpeg[i] == 0xFF) {
    final marker = jpeg[i + 1];
    if (marker == 0xDA || marker == 0xD9) break;
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (marker == 0xE1 && String.fromCharCodes(jpeg.sublist(i + 4, i + 8)) == 'Exif') {
      final t = Uint8List.sublistView(jpeg, i + 10, i + 2 + len);
      final big = t[0] == 0x4D;
      int u16(int o) => big ? (t[o] << 8) | t[o + 1] : t[o] | (t[o + 1] << 8);
      int u32(int o) => big
          ? (t[o] << 24) | (t[o + 1] << 16) | (t[o + 2] << 8) | t[o + 3]
          : t[o] | (t[o + 1] << 8) | (t[o + 2] << 16) | (t[o + 3] << 24);
      final ifd0 = u32(4);
      for (var k = 0; k < u16(ifd0); k++) {
        final e = ifd0 + 2 + k * 12;
        if (u16(e) == 0x0112) return u16(e + 8);
      }
    }
    i += 2 + len;
  }
  return null;
}

/// A PNG with an eXIf chunk and text chunks that mention a position.
Uint8List gpsPng() {
  List<int> chunk(String type, List<int> data) =>
      [..._be32(data.length), ...type.codeUnits, ...data, 0, 0, 0, 0]; // CRC not checked by the sanitizer
  final b = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(chunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]))
    ..add(chunk('eXIf', exifWithGps(lat: 10.123, lon: 20.456).sublist(6)))
    ..add(chunk('tEXt', 'Comment\x00gps 10.123 20.456'.codeUnits))
    ..add(chunk('IDAT', [1, 2, 3, 4]))
    ..add(chunk('IEND', const []))
    ..add('TRAILER-GPS'.codeUnits);
  return b.toBytes();
}

List<int> _be32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
