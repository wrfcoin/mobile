import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/api/api_response.dart';

class WeatherMapScreen extends ConsumerStatefulWidget {
  const WeatherMapScreen({super.key});

  @override
  ConsumerState<WeatherMapScreen> createState() => _WeatherMapScreenState();
}

class _WeatherMapScreenState extends ConsumerState<WeatherMapScreen> {
  List<Marker> _markers = [];

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get(ApiConstants.weatherStations);
      final list = unwrapListPayload(response.data);

      final markers = <Marker>[];
      for (final item in list) {
        final station = Map<String, dynamic>.from(item as Map);
        final location = station['location'];
        final lat =
            ((station['lat'] ?? station['latitude']) as num?)?.toDouble() ??
            (location is Map ? (location['lat'] as num?)?.toDouble() : null);
        final lng =
            ((station['lng'] ?? station['lon'] ?? station['longitude']) as num?)
                ?.toDouble() ??
            (location is Map ? (location['lon'] as num?)?.toDouble() : null);
        final name = station['name']?.toString() ?? '';

        if (lat != null && lng != null) {
          markers.add(
            Marker(
              point: LatLng(lat, lng),
              child: _StationMarker(label: name),
            ),
          );
        }
      }

      if (mounted) {
        setState(() => _markers = markers);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load station data')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weather Map')),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(39.8283, -98.5795), // Center of US
          initialZoom: 4,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.wrfcoin.mobile',
          ),
          MarkerLayer(markers: _markers),
        ],
      ),
    );
  }
}

class _StationMarker extends StatelessWidget {
  final String label;
  const _StationMarker({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ),
        const Icon(Icons.location_on, color: AppColors.primary, size: 24),
      ],
    );
  }
}
