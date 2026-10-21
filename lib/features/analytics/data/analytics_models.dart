class AnalyticsReadingSample {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double pressureHpa;
  final bool synced;
  final int heatmapRow;
  final int heatmapColumn;
  final int dailyCollectionCount;
  final double dailyEarnedWrf;

  const AnalyticsReadingSample({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.pressureHpa,
    required this.synced,
    this.heatmapRow = 0,
    this.heatmapColumn = 0,
    this.dailyCollectionCount = 0,
    this.dailyEarnedWrf = 0,
  });
}

class AnalyticsHeatmapBin {
  final int row;
  final int column;
  final int count;

  const AnalyticsHeatmapBin({
    required this.row,
    required this.column,
    required this.count,
  });
}

class AnalyticsTrendPoint {
  final DateTime day;
  final double value;

  const AnalyticsTrendPoint({required this.day, required this.value});
}

class AnalyticsSummary {
  final int totalReadings;
  final int syncedReadings;
  final int pendingReadings;
  final double earnedWrf;
  final bool rewardTotalsAvailable;
  final double averagePressureHpa;
  final DateTime? firstReadingAt;
  final DateTime? lastReadingAt;
  final int heatmapPeakCount;

  const AnalyticsSummary({
    required this.totalReadings,
    required this.syncedReadings,
    required this.pendingReadings,
    required this.earnedWrf,
    required this.rewardTotalsAvailable,
    required this.averagePressureHpa,
    required this.firstReadingAt,
    required this.lastReadingAt,
    required this.heatmapPeakCount,
  });
}

class AnalyticsSnapshot {
  final AnalyticsSummary summary;
  final List<AnalyticsReadingSample> readings;
  final List<AnalyticsHeatmapBin> heatmapBins;
  final List<AnalyticsTrendPoint> collectionTrend;
  final List<AnalyticsTrendPoint> earningTrend;
  final DateTime generatedAt;

  const AnalyticsSnapshot({
    required this.summary,
    required this.readings,
    required this.heatmapBins,
    required this.collectionTrend,
    required this.earningTrend,
    required this.generatedAt,
  });
}
