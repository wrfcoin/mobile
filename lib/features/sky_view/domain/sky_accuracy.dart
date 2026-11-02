/// Compass accuracy in the words the app shows.
enum SkyAccuracy {
  good('Good'),
  fair('Fair'),
  poor('Poor'),
  unknown('Unknown');

  final String label;
  const SkyAccuracy(this.label);
  bool get low => this == poor;
}

SkyAccuracy _worst(SkyAccuracy a, SkyAccuracy b) {
  if (a == SkyAccuracy.unknown) return b;
  if (b == SkyAccuracy.unknown) return a;
  return a.index > b.index ? a : b;
}

/// From SensorEvent.accuracy (SENSOR_STATUS_*: 3 high, 2 medium, 1 low,
/// 0 unreliable, -1 no contact) and values[4], the rotation vector's estimated
/// heading accuracy in radians. Android documents -1 for "not available"; zero
/// is treated the same, since no real heading is known to zero error. The worse
/// of the two signals wins.
SkyAccuracy rotationVectorAccuracy(int status, double headingRadians) {
  final fromStatus = switch (status) {
    3 => SkyAccuracy.good,
    2 => SkyAccuracy.fair,
    1 || 0 || -1 => SkyAccuracy.poor,
    _ => SkyAccuracy.unknown,
  };
  if (!headingRadians.isFinite || headingRadians <= 0) return fromStatus;
  final degrees = headingRadians * 57.29577951;
  final fromHeading = degrees <= 10
      ? SkyAccuracy.good
      : degrees <= 25
      ? SkyAccuracy.fair
      : SkyAccuracy.poor;
  return _worst(fromStatus, fromHeading);
}

/// The fallback has no status to read. The Earth's field is 25 to 65 microtesla
/// everywhere, so a reading outside that means something magnetic is nearby.
/// Otherwise "fair" is the best this path can honestly claim.
SkyAccuracy fallbackAccuracy(double magneticMicrotesla) =>
    magneticMicrotesla >= 25 && magneticMicrotesla <= 65
    ? SkyAccuracy.fair
    : SkyAccuracy.poor;
