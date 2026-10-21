import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/api/api_response.dart';

/// Data model for a single sensor reading snapshot.
class StationReading {
  final DateTime timestamp;
  final double temperature;
  final int humidity;
  final double pressure;

  const StationReading({
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.pressure,
  });
}

/// Data model representing a station's complete profile.
class StationProfile {
  final String id;
  final String name;
  final String model;
  final String status;
  final DateTime memberSince;
  final int totalReadings;
  final double uptimePercent;
  final List<StationReading> recentReadings;

  // Impact stats
  final int forecastContributions;
  final double coverageRadiusKm;
  final int contributorPercentile;

  // Rolling 24h stats
  final double tempMin24h;
  final double tempMax24h;
  final double tempAvg24h;
  final double humidityMin24h;
  final double humidityMax24h;
  final double humidityAvg24h;
  final double pressureMin24h;
  final double pressureMax24h;
  final double pressureAvg24h;

  // Uptime heatmap: day-of-year -> number of readings (0-48 for 30-min intervals)
  final Map<int, int> uptimeHeatmap;

  const StationProfile({
    required this.id,
    required this.name,
    required this.model,
    required this.status,
    required this.memberSince,
    required this.totalReadings,
    required this.uptimePercent,
    required this.recentReadings,
    required this.forecastContributions,
    required this.coverageRadiusKm,
    required this.contributorPercentile,
    required this.tempMin24h,
    required this.tempMax24h,
    required this.tempAvg24h,
    required this.humidityMin24h,
    required this.humidityMax24h,
    required this.humidityAvg24h,
    required this.pressureMin24h,
    required this.pressureMax24h,
    required this.pressureAvg24h,
    required this.uptimeHeatmap,
  });
}

/// Provides a [StationProfile] for a given wallet address (operator).
///
/// Makes a real HTTP call to GET /api/operators/:walletAddress/profile.
final stationProfileProvider = FutureProvider.family<StationProfile, String>((
  ref,
  walletAddress,
) async {
  final apiClient = ref.read(apiClientProvider);
  return _loadProfile(apiClient, walletAddress);
});

Future<StationProfile> _loadProfile(
  ApiClient apiClient,
  String walletAddress,
) async {
  try {
    final response = await apiClient.dio.get(
      ApiConstants.operatorProfile(walletAddress),
    );

    final outer = unwrapMapPayload(response.data);
    // Backend wraps the profile under a 'profile' key:
    // { success: true, profile: { ... } }
    final raw = outer['profile'];
    final data = (raw is Map<String, dynamic>)
        ? raw
        : (outer.isNotEmpty ? outer : const <String, dynamic>{});

    final joinedAtRaw = data['joinedAt'] as String?;
    final memberSince = joinedAtRaw != null
        ? DateTime.tryParse(joinedAtRaw) ?? DateTime.now()
        : DateTime.now();

    final displayName = data['displayName'] as String?;
    final shortAddr = walletAddress.length >= 10
        ? '${walletAddress.substring(0, 6).toUpperCase()}...${walletAddress.substring(walletAddress.length - 4).toUpperCase()}'
        : walletAddress.toUpperCase();
    final name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : 'Station $shortAddr';

    final totalSubmissions = (data['totalSubmissions'] as num?)?.toInt() ?? 0;
    final qualityScore = (data['qualityScore'] as num?)?.toDouble() ?? 0.0;
    final rank = (data['rank'] as num?)?.toInt() ?? 0;

    final badgesRaw = data['badges'];
    final badges = badgesRaw is List
        ? badgesRaw.map((b) => b.toString()).toList()
        : <String>[];

    // forecastContributions maps to totalSubmissions from the operator profile.
    // contributorPercentile is derived from rank (lower rank = better percentile).
    // We do not have per-station reading arrays from this endpoint, so recentReadings
    // and heatmap are left empty; callers that need them should use a dedicated
    // station readings endpoint.
    return StationProfile(
      id: walletAddress,
      name: name,
      model: badges.isNotEmpty ? badges.first : 'WRFCoin Station',
      status: 'online',
      memberSince: memberSince,
      totalReadings: totalSubmissions,
      uptimePercent: qualityScore.clamp(0.0, 100.0),
      recentReadings: const [],
      forecastContributions: totalSubmissions,
      coverageRadiusKm: 0.0,
      contributorPercentile: rank > 0 ? rank : 0,
      tempMin24h: 0.0,
      tempMax24h: 0.0,
      tempAvg24h: 0.0,
      humidityMin24h: 0.0,
      humidityMax24h: 0.0,
      humidityAvg24h: 0.0,
      pressureMin24h: 0.0,
      pressureMax24h: 0.0,
      pressureAvg24h: 0.0,
      uptimeHeatmap: const {},
    );
  } on DioException {
    rethrow;
  }
}
