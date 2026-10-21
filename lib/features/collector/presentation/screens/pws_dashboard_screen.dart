import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/dio_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/formatting/app_formatters.dart';
import '../../../../core/formatting/reported_amount.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../core/feature_flags/feature_flags.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/api/api_response.dart';
import '../providers/sensor_stream_provider.dart';
import '../widgets/live_sensor_metrics.dart';
import '../widgets/sparkline_chart.dart';
import 'station_profile_screen.dart';
import 'ambient_onboarding_screen.dart';

class PwsDashboardScreen extends ConsumerStatefulWidget {
  const PwsDashboardScreen({super.key});

  @override
  ConsumerState<PwsDashboardScreen> createState() => _PwsDashboardScreenState();
}

class _PwsDashboardScreenState extends ConsumerState<PwsDashboardScreen> {
  bool _loading = true;
  Failure? _error;
  List<_PwsStation> _stations = [];

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get(ApiConstants.oracleStations);
      final list = unwrapListPayload(response.data);

      final stationMaps = list
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

      final stations = await Future.wait(
        stationMaps.map((stationMap) async {
          final stationId = stationMap['id']?.toString() ?? '';
          final status = stationMap['status']?.toString() ?? 'offline';

          double temperature = 0;
          int humidity = 0;
          double pressure = 0;
          String lastReading = 'N/A';

          if (status == 'online') {
            try {
              final weatherResponse = await apiClient.dio.get(
                ApiConstants.weatherRealtime(stationId),
              );
              // Lane 1: use unwrapMapPayload + field aliases to handle varying
              // backend response shapes (temperature/tempC, pressure/pressureHpa,
              // nested 'current' object). More defensive than a direct cast.
              final weather = unwrapMapPayload(weatherResponse.data);
              final current = weather['current'];
              temperature =
                  ((weather['temperature'] ??
                              weather['tempC'] ??
                              (current is Map ? current['temperature'] : null))
                          as num?)
                      ?.toDouble() ??
                  0;
              humidity =
                  ((weather['humidity'] ??
                              (current is Map ? current['humidity'] : null))
                          as num?)
                      ?.toInt() ??
                  0;
              pressure =
                  ((weather['pressure'] ??
                              weather['pressureHpa'] ??
                              (current is Map ? current['pressure'] : null))
                          as num?)
                      ?.toDouble() ??
                  0;
              lastReading =
                  (weather['lastReading'] ??
                          weather['timestamp'] ??
                          (current is Map ? current['timestamp'] : null))
                      ?.toString() ??
                  'N/A';
            } catch (_) {
              // Weather data unavailable, keep defaults
            }
          }

          return _PwsStation(
            id: stationId,
            name: stationMap['name']?.toString() ?? 'Unknown',
            model: stationMap['model']?.toString() ?? 'Unknown',
            status: status,
            lastReading: lastReading,
            temperature: temperature,
            humidity: humidity,
            pressure: pressure,
            // A separate endpoint's WRF contract cannot label this bare field.
            earnings: declaredWrfAmount(
              stationMap['earnings'],
              stationMap['amountUnits'],
              'earnings',
            ),
          );
        }),
      );

      if (mounted) {
        setState(() {
          _stations = stations;
          _loading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = DioErrorMapper.map(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ServerFailure(e.toString());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(appPreferencesProvider).preferences;
    final flags = ref.watch(featureFlagsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather Stations'),
        actions: [
          if (flags.enablePwsAutoDiscovery)
            IconButton(
              tooltip: 'Connect Ambient station',
              icon: const Icon(Icons.add_link),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AmbientOnboardingScreen(),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Loading linked station status and latest readings...',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  SizedBox(height: 16),
                  Expanded(child: ShimmerList(count: 2, height: 140)),
                ],
              ),
            )
          : _error != null
          ? AppErrorWidget.fromFailure(_error!, onRetry: _loadStations)
          : _stations.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.router, size: 64, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text(
                    'No stations linked',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Link a weather station to start earning credits',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Live Readings card
                _LiveReadingsCard(),
                const SizedBox(height: 16),

                // Summary card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.router,
                          size: 32,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_stations.length} Linked Stations',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${_stations.where((s) => s.status == "online").length} online',
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            // Link new station flow
                          },
                          child: const Text('Add Station'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Station cards
                ..._stations.map(
                  (station) =>
                      _StationCard(station: station, preferences: preferences),
                ),
              ],
            ),
    );
  }
}

class _PwsStation {
  final String id;
  final String name;
  final String model;
  final String status;
  final String lastReading;
  final double temperature;
  final int humidity;
  final double pressure;
  final String? earnings;

  _PwsStation({
    required this.id,
    required this.name,
    required this.model,
    required this.status,
    required this.lastReading,
    required this.temperature,
    required this.humidity,
    required this.pressure,
    required this.earnings,
  });
}

class _StationCard extends StatelessWidget {
  final _PwsStation station;
  final AppPreferences preferences;

  const _StationCard({required this.station, required this.preferences});

  @override
  Widget build(BuildContext context) {
    final isOnline = station.status == 'online';
    final statusIcon = isOnline
        ? Icons.wifi_tethering
        : Icons.portable_wifi_off;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: 'Open station profile for ${station.name}',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StationProfileScreen(stationId: station.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      statusIcon,
                      size: 16,
                      color: isOnline ? AppColors.success : AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        station.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      station.status.toUpperCase(),
                      style: TextStyle(
                        color: isOnline ? AppColors.success : AppColors.error,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${station.model} | Last: ${AppFormatters.formatIsoTimestamp(context, preferences, station.lastReading)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (isOnline) ...[
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MetricColumn(
                        label: 'Temp',
                        value: AppFormatters.formatTemperature(
                          context,
                          preferences,
                          station.temperature,
                        ),
                      ),
                      _MetricColumn(
                        label: 'Humidity',
                        value: '${station.humidity}%',
                      ),
                      _MetricColumn(
                        label: 'Pressure',
                        value: AppFormatters.formatPressure(
                          context,
                          preferences,
                          station.pressure,
                        ),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            station.earnings == null
                                ? 'Earnings unavailable'
                                : '${station.earnings} earned',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  final String label;
  final String value;

  const _MetricColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

/// Card section that shows [LiveSensorMetrics] with a sparkline connected to
/// the latest accelerometer magnitude from the sensor stream.
class _LiveReadingsCard extends ConsumerWidget {
  // ignore: prefer_const_constructors_in_immutables
  _LiveReadingsCard();

  // Accumulate magnitude history across rebuilds via an instance list.
  // We keep at most 30 data points for the sparkline.
  static final List<double> _magnitudeHistory = <double>[];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSnap = ref.watch(sensorStreamProvider);
    double? liveValue;

    asyncSnap.whenData((snapshot) {
      liveValue = snapshot.accelerometerMagnitude;
      if (liveValue != null) {
        _magnitudeHistory.add(liveValue!);
        if (_magnitudeHistory.length > 30) {
          _magnitudeHistory.removeAt(0);
        }
      }
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Live Readings',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const LiveSensorMetrics(),
            if (_magnitudeHistory.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Motion',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              SparklineChart(
                values: List<double>.from(_magnitudeHistory),
                liveValue: liveValue,
                height: 48,
                color: AppColors.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
