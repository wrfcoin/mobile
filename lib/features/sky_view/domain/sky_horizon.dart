import '../../weather/domain/models/coarse_location.dart';
import 'sky_astronomy.dart';
import 'sky_moon.dart';

class HorizonEvents {
  final DateTime? rise, set;
  const HorizonEvents({this.rise, this.set});
}

/// First geometric zero-altitude crossings in [start, start + 24 hours).
/// Samples one-minute intervals and refines sign changes to within a second.
/// This is an approximate finder, not apparent limb rise/set: no refraction,
/// terrain or observer elevation. The Moon includes parallax, since it shifts
/// the crossing by minutes. Very brief grazing crossings may be missed.
/// Returns null if the complete window exceeds the existing ephemeris range.
HorizonEvents? nextHorizonEvents(
  SkyObject object,
  DateTime start,
  CoarseLocation cell,
) {
  final utc = start.toUtc();
  final end = utc.add(const Duration(hours: 24));
  if (utc.year < 1800 || end.year > 2050) return null;
  if (!object.position.ra.isFinite ||
      !object.position.dec.isFinite ||
      object.position.dec.abs() > 90) {
    throw RangeError('Invalid sky position');
  }
  // Catalog coordinates are J2000; moving bodies need a fresh J2000 position
  // at every sample, then all use the shared precession/horizon transform.
  double altitude(DateTime time) {
    final position = movingPosition(object.id, time) ?? object.position;
    final at = SkyObject(
      object.id,
      object.name,
      '',
      position,
      object.magnitude,
    );
    return observedHorizontal(at, time, cell).altitude;
  }

  DateTime refine(DateTime left, DateTime right, bool rising) {
    while (right.difference(left) > const Duration(seconds: 1)) {
      final middle = left.add(
        Duration(microseconds: right.difference(left).inMicroseconds ~/ 2),
      );
      if ((altitude(middle) > 0) == rising) {
        right = middle;
      } else {
        left = middle;
      }
    }
    return left.add(
      Duration(microseconds: right.difference(left).inMicroseconds ~/ 2),
    );
  }

  DateTime? rise, set;
  var previousTime = utc;
  var previous = altitude(utc);
  for (var minute = 1; minute <= 24 * 60; minute++) {
    final time = utc.add(Duration(minutes: minute));
    final current = altitude(time);
    if (rise == null && previous <= 0 && current > 0) {
      rise = refine(previousTime, time, true);
    }
    if (set == null && previous >= 0 && current < 0) {
      set = refine(previousTime, time, false);
    }
    if (rise != null && set != null) break;
    previousTime = time;
    previous = current;
  }
  return HorizonEvents(rise: rise, set: set);
}
