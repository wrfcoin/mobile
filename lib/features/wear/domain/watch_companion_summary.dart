import '../../collector/data/models/sensor_reading_model.dart';

class WatchCompanionSummary {
  const WatchCompanionSummary({
    required this.lastPressureHpa,
    required this.readingsInWindow,
    required this.lastSeenAtUtc,
    required this.passiveCollectionEnabled,
  });

  factory WatchCompanionSummary.fromReadings({
    required Iterable<SensorReadingModel> readings,
    required Duration window,
    required bool passiveCollectionEnabled,
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(window);
    final windowed =
        readings
            .where((reading) => !reading.timestamp.toUtc().isBefore(cutoff))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final latest = windowed.isNotEmpty ? windowed.last : null;
    return WatchCompanionSummary(
      lastPressureHpa: latest?.pressureHpa,
      readingsInWindow: windowed.length,
      lastSeenAtUtc: latest?.timestamp.toUtc() ?? cutoff,
      passiveCollectionEnabled: passiveCollectionEnabled,
    );
  }

  final double? lastPressureHpa;
  final int readingsInWindow;
  final DateTime lastSeenAtUtc;
  final bool passiveCollectionEnabled;

  String summarize() {
    if (lastPressureHpa == null) {
      return passiveCollectionEnabled
          ? 'No recent pressure samples. Passive collection is enabled.'
          : 'No recent pressure samples available.';
    }

    return 'Latest ${lastPressureHpa!.toStringAsFixed(1)} hPa, '
        '$readingsInWindow sample(s) in window. '
        'Passive collection ${passiveCollectionEnabled ? 'enabled' : 'disabled'}.';
  }
}
