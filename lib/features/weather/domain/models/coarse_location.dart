/// A device position rounded to a 0.1° grid (~11 km) before it leaves the
/// device.
///
/// Weather requests are keyed by this type only, so an unrounded fix cannot
/// reach a URL: the only public constructor rounds. Owner ruling 2026-09-28:
/// 0.1° on-device rounding, sent only over the tailnet API.
class CoarseLocation {
  /// Grid step in degrees.
  static const double gridDegrees = 0.1;

  final double latitude;
  final double longitude;

  const CoarseLocation._(this.latitude, this.longitude);

  /// Rounds an exact fix to the 0.1° grid.
  factory CoarseLocation.round(double latitude, double longitude) =>
      CoarseLocation._(_round(latitude), _round(longitude));

  /// One coordinate rounded to the 0.1° grid (the same rounding as [CoarseLocation.round]).
  static double coarsen(double value) => _round(value);

  /// `+ 0.0` turns a -0.0 result into +0.0: the sign of a zero would say
  /// which half of the cell the fix is in.
  static double _round(double value) => (value * 10).roundToDouble() / 10 + 0.0;

  /// The cell in integer tenths of a degree (the wire form of the
  /// authenticated temperature-history route). Never finer than the grid.
  int get latE1 => (latitude * 10).round();
  int get lonE1 => (longitude * 10).round();

  /// `lat,lon` with exactly one decimal, as the backend's weather routes
  /// accept it in the path.
  String get pathSegment =>
      '${latitude.toStringAsFixed(1)},${longitude.toStringAsFixed(1)}';

  @override
  bool operator ==(Object other) =>
      other is CoarseLocation &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'CoarseLocation($pathSegment)';
}
