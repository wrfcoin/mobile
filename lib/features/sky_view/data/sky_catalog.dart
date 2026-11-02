import '../../weather/domain/models/coarse_location.dart';
import '../domain/sky_astronomy.dart';
import '../domain/sky_attitude.dart';
import '../domain/sky_moon.dart';
import 'bright_stars.dart';

/// One object, placed for one observer at one moment.
class SkyFix {
  final SkyObject object;
  final Horizontal horizontal;
  final Vec3 direction;
  SkyFix(this.object, this.horizontal)
    : direction = Vec3.fromAzAlt(horizontal.azimuth, horizontal.altitude);

  bool get isSolarSystem => object.magnitude.isNaN;
}

/// Everything the map can draw. A future layer is one more source here.
final List<List<SkyObject> Function(DateTime utc)> skySources = [
  (_) => brightStars,
  solarSystem,
  (utc) => [moonObject(utc)],
];

/// Places every catalog object. The map draws only what this returns, so it
/// cannot show a star that is not real.
List<SkyFix> computeSky(DateTime utc, CoarseLocation cell) => [
  for (final source in skySources)
    for (final object in source(utc))
      SkyFix(object, observedHorizontal(object, utc, cell)),
];
