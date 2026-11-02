import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/sky_astronomy.dart';

const skyStarCatalogAsset = 'assets/sky/sky_catalog.bin';

class SkyConstellation {
  final String abbreviation, name;
  const SkyConstellation(this.abbreviation, this.name);
}

/// A name placed on the map. Serpens has two, one for each part.
class SkyConstellationLabel {
  final SkyConstellation constellation;
  final String text;
  final Equatorial position;
  final double x, y, z;
  SkyConstellationLabel(this.constellation, this.text, this.position)
    : x = _x(position),
      y = _y(position),
      z = _z(position);
}

const _radians = math.pi / 180;
double _x(Equatorial p) =>
    math.cos(p.dec * _radians) * math.cos(p.ra * _radians);
double _y(Equatorial p) =>
    math.cos(p.dec * _radians) * math.sin(p.ra * _radians);
double _z(Equatorial p) => math.sin(p.dec * _radians);

class _Polygon {
  final int constellation;
  final Float32List ra, dec;
  final bool aroundNorthPole, aroundSouthPole;
  final double minDec, maxDec;
  _Polygon(
    this.constellation,
    this.ra,
    this.dec,
    this.aroundNorthPole,
    this.aroundSouthPole,
    this.minDec,
    this.maxDec,
  );

  /// A ray north along the point's meridian: an odd number of crossings means
  /// inside, reversed for the one polygon that holds the ray's end, the pole.
  bool contains(double pointRa, double pointDec) {
    if (pointDec < minDec) return aroundSouthPole;
    if (pointDec > maxDec) return aroundNorthPole;
    var inside = false;
    final count = ra.length;
    var previous = count - 1;
    for (var i = 0; i < count; previous = i, i++) {
      final step = (ra[i] - ra[previous] + 180) % 360 - 180;
      final offset = (pointRa - ra[previous] + 180) % 360 - 180;
      final spans =
          (step > 0 && offset >= 0 && offset < step) ||
          (step < 0 && offset >= step && offset < 0);
      if (spans &&
          dec[previous] + (dec[i] - dec[previous]) * offset / step > pointDec) {
        inside = !inside;
      }
    }
    return inside != aroundNorthPole;
  }
}

/// The bundled naked-eye catalog: every star as flat arrays, brightest first,
/// with the constellation figures as pairs of star indexes.
class SkyStarCatalog {
  final Uint16List hr;
  final Float32List ra, dec;
  final Int16List _magnitude;
  final Uint8List _constellation;
  final List<int> _designationStart;
  final Uint8List _bytes;

  /// x, y, z per star: the J2000 direction.
  final Float32List unit;

  /// Two star indexes per segment.
  final Uint16List segments;
  final Uint8List segmentConstellation;
  final List<SkyConstellation> constellations;
  final List<SkyConstellationLabel> labels;
  final List<_Polygon> _polygons;

  SkyStarCatalog._(
    this.hr,
    this.ra,
    this.dec,
    this._magnitude,
    this._constellation,
    this._designationStart,
    this._bytes,
    this.unit,
    this.segments,
    this.segmentConstellation,
    this.constellations,
    this.labels,
    this._polygons,
  );

  int get starCount => hr.length;
  double magnitude(int star) => _magnitude[star] / 100;
  SkyConstellation constellationOf(int star) =>
      constellations[_constellation[star]];

  String designation(int star) {
    final start = _designationStart[star];
    return utf8.decode(
      Uint8List.sublistView(_bytes, start + 1, start + 1 + _bytes[start]),
    );
  }

  /// The star as an object the map's details and alignment already understand.
  SkyObject object(int star) => SkyObject(
    'HR${hr[star]}',
    designation(star),
    constellationOf(star).abbreviation,
    Equatorial(ra[star], dec[star]),
    magnitude(star),
  );

  /// The IAU constellation holding a J2000 position, or null on the very rare
  /// point that falls in a rounding gap between two boundaries.
  SkyConstellation? constellationAt(double ra, double dec) {
    final wrapped = ra % 360;
    for (final polygon in _polygons) {
      if (polygon.contains(wrapped, dec)) {
        return constellations[polygon.constellation];
      }
    }
    return null;
  }

  /// How many boundaries hold a position. The sky is divided, so this is one
  /// everywhere but in a rounding gap.
  @visibleForTesting
  int boundariesHolding(double ra, double dec) {
    final wrapped = ra % 360;
    var count = 0;
    for (final polygon in _polygons) {
      if (polygon.contains(wrapped, dec)) count++;
    }
    return count;
  }

  factory SkyStarCatalog.decode(ByteData data) {
    final bytes = Uint8List.sublistView(data);
    var at = 0;
    int u8() => bytes[at++];
    int u16() {
      final value = data.getUint16(at, Endian.little);
      at += 2;
      return value;
    }

    double f32() {
      final value = data.getFloat32(at, Endian.little);
      at += 4;
      return value;
    }

    String text() {
      final length = u8();
      final value = utf8.decode(Uint8List.sublistView(bytes, at, at + length));
      at += length;
      return value;
    }

    if (ascii.decode(Uint8List.sublistView(bytes, 0, 4)) != 'WSKY') {
      throw const FormatException('Not a sky catalog');
    }
    at = 4;
    if (u16() != 1) throw const FormatException('Unknown sky catalog version');
    final starCount = u16(), segmentCount = u16(), constellationCount = u16();
    final labelCount = u16(), polygonCount = u16();

    final hr = Uint16List(starCount);
    for (var i = 0; i < starCount; i++) {
      hr[i] = u16();
    }
    final ra = Float32List(starCount);
    for (var i = 0; i < starCount; i++) {
      ra[i] = f32();
    }
    final dec = Float32List(starCount);
    for (var i = 0; i < starCount; i++) {
      dec[i] = f32();
    }
    final magnitude = Int16List(starCount);
    for (var i = 0; i < starCount; i++) {
      magnitude[i] = data.getInt16(at, Endian.little);
      at += 2;
    }
    final constellation = Uint8List(starCount);
    for (var i = 0; i < starCount; i++) {
      constellation[i] = u8();
    }
    final designationStart = List<int>.filled(starCount, 0);
    for (var i = 0; i < starCount; i++) {
      designationStart[i] = at;
      at += 1 + bytes[at];
    }
    final constellations = <SkyConstellation>[
      for (var i = 0; i < constellationCount; i++)
        () {
          final abbreviation = ascii.decode(
            Uint8List.sublistView(bytes, at, at + 3),
          );
          at += 3;
          return SkyConstellation(abbreviation, text());
        }(),
    ];
    final labels = <SkyConstellationLabel>[
      for (var i = 0; i < labelCount; i++)
        () {
          final owner = constellations[u8()];
          final labelRa = f32(), labelDec = f32();
          return SkyConstellationLabel(
            owner,
            text(),
            Equatorial(labelRa, labelDec),
          );
        }(),
    ];
    final segments = Uint16List(segmentCount * 2);
    final segmentConstellation = Uint8List(segmentCount);
    for (var i = 0; i < segmentCount; i++) {
      segments[i * 2] = u16();
      segments[i * 2 + 1] = u16();
      segmentConstellation[i] = u8();
    }
    final polygons = <_Polygon>[
      for (var i = 0; i < polygonCount; i++)
        () {
          final owner = u8();
          final count = u16();
          final polygonRa = Float32List(count), polygonDec = Float32List(count);
          var winding = 0.0, sum = 0.0;
          var low = 90.0, high = -90.0;
          for (var p = 0; p < count; p++) {
            polygonRa[p] = f32();
            polygonDec[p] = f32();
            sum += polygonDec[p];
            low = math.min(low, polygonDec[p]);
            high = math.max(high, polygonDec[p]);
            if (p > 0) {
              winding += (polygonRa[p] - polygonRa[p - 1] + 180) % 360 - 180;
            }
          }
          winding += (polygonRa[0] - polygonRa[count - 1] + 180) % 360 - 180;
          return _Polygon(
            owner,
            polygonRa,
            polygonDec,
            winding.abs() > 180 && sum > 0,
            winding.abs() > 180 && sum <= 0,
            low,
            high,
          );
        }(),
    ];
    if (at != bytes.length) throw const FormatException('Sky catalog length');

    final unit = Float32List(starCount * 3);
    for (var i = 0; i < starCount; i++) {
      final position = Equatorial(ra[i], dec[i]);
      unit[i * 3] = _x(position);
      unit[i * 3 + 1] = _y(position);
      unit[i * 3 + 2] = _z(position);
    }
    return SkyStarCatalog._(
      hr,
      ra,
      dec,
      magnitude,
      constellation,
      designationStart,
      bytes,
      unit,
      segments,
      segmentConstellation,
      constellations,
      labels,
      polygons,
    );
  }
}

Future<SkyStarCatalog>? _loading;

/// Read once from the app's own files, then shared. Never from the network.
Future<SkyStarCatalog> loadSkyStarCatalog([AssetBundle? bundle]) {
  return _loading ??= _read(bundle ?? rootBundle);
}

/// Each widget test has its own fake clock, which a shared future cannot cross.
@visibleForTesting
void forgetSkyStarCatalog() => _loading = null;

Future<SkyStarCatalog> _read(AssetBundle bundle) async {
  try {
    return SkyStarCatalog.decode(await bundle.load(skyStarCatalogAsset));
  } catch (_) {
    _loading = null; // The next visit tries again.
    rethrow;
  }
}
