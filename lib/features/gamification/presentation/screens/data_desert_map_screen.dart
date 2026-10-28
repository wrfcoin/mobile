import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/location/location_service.dart';

/// Shown when the node did not report a multiplier. Never replaced by a guess.
const String kMultiplierUnavailable = 'unavailable';

/// Formats the node-reported multiplier, or [kMultiplierUnavailable] when absent.
String formatRewardMultiplier(double? value) {
  if (value == null) return kMultiplierUnavailable;
  return value == value.roundToDouble()
      ? '${value.toInt()}×'
      : '${value.toStringAsFixed(1)}×';
}

class DataDesertMapScreen extends ConsumerStatefulWidget {
  const DataDesertMapScreen({super.key});

  @override
  ConsumerState<DataDesertMapScreen> createState() =>
      _DataDesertMapScreenState();
}

class _DataDesertMapScreenState extends ConsumerState<DataDesertMapScreen> {
  final _mapController = MapController();
  List<CoverageZone> _zones = const [];
  Position? _userPosition;
  bool _loadingLocation = false;
  bool _loadingZones = true;

  @override
  void initState() {
    super.initState();
    _loadCoverageZones();
    _fetchUserLocation();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadCoverageZones() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get(ApiConstants.coverageZones);
      final list = _extractList(response.data);
      final zones = list
          .whereType<Map>()
          .map((item) => CoverageZone.fromJson(Map<String, dynamic>.from(item)))
          .whereType<CoverageZone>()
          .toList(growable: false);
      if (mounted) setState(() { _zones = zones; _loadingZones = false; });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingZones = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load coverage data')),
        );
      }
    }
  }

  Future<void> _fetchUserLocation() async {
    setState(() => _loadingLocation = true);
    final position =
        await ref.read(locationServiceProvider).getCurrentPosition();
    if (mounted) setState(() { _userPosition = position; _loadingLocation = false; });
  }

  void _centerOnUser() {
    final pos = _userPosition;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
      return;
    }
    _mapController.move(LatLng(pos.latitude, pos.longitude), 10);
  }

  void _onZoneTap(CoverageZone zone) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ZoneDetailSheet(zone: zone),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Desert Map')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(39.8283, -98.5795),
              initialZoom: 4,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.wrfcoin.mobile',
              ),
              CircleLayer(
                circles: _zones
                    .map((zone) => CircleMarker(
                          point: LatLng(zone.lat, zone.lng),
                          radius: zone.radius,
                          color: zone.color.withValues(alpha: 0.15),
                          borderColor: zone.color.withValues(alpha: 0.4),
                          borderStrokeWidth: 2,
                        ))
                    .toList(growable: false),
              ),
              // Tappable zone markers (invisible but capture taps)
              MarkerLayer(
                markers: _zones
                    .map((zone) => Marker(
                          point: LatLng(zone.lat, zone.lng),
                          width: zone.radius * 2,
                          height: zone.radius * 2,
                          child: GestureDetector(
                            key: ValueKey('zone_${zone.lat}_${zone.lng}'),
                            onTap: () => _onZoneTap(zone),
                            child: const SizedBox.expand(),
                          ),
                        ))
                    .toList(growable: false),
              ),
              if (_userPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _userPosition!.latitude,
                        _userPosition!.longitude,
                      ),
                      width: 36,
                      height: 36,
                      child: const _UserLocationMarker(),
                    ),
                  ],
                ),
            ],
          ),
          // Legend
          Positioned(
            top: 16,
            left: 16,
            child: _Legend(zones: _zones),
          ),
          // Loading indicator
          if (_loadingZones)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
          // "Start collecting here" CTA
          Positioned(
            bottom: 16,
            left: 16,
            right: 68,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.sensors),
              label: const Text('Start Collecting Here'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'center_on_user',
        onPressed: _loadingLocation ? null : _centerOnUser,
        tooltip: 'Center on my location',
        child: _loadingLocation
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
      ),
    );
  }

  List<dynamic> _extractList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is! Map) return const <dynamic>[];
    final map = Map<String, dynamic>.from(payload);
    for (final key in const ['zones', 'coverageZones', 'items', 'data']) {
      final candidate = map[key];
      if (candidate is List) return candidate;
      if (candidate is Map) {
        final nested = _extractList(candidate);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const <dynamic>[];
  }
}

// ── Zone detail bottom sheet ──────────────────────────────────────────────────

class _ZoneDetailSheet extends StatelessWidget {
  const _ZoneDetailSheet({required this.zone});
  final CoverageZone zone;

  @override
  Widget build(BuildContext context) {
    // Only the node's value is shown. No tier multiplier is ever invented here.
    final multiplierText = formatRewardMultiplier(zone.rewardMultiplier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: zone.color.withValues(alpha: 0.3),
                  border: Border.all(color: zone.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _typeLabel(zone.type),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Reward multiplier', value: multiplierText),
          _InfoRow(
            label: 'Zone type',
            value: zone.type[0].toUpperCase() + zone.type.substring(1),
          ),
          _InfoRow(
            label: 'Coordinates',
            value:
                '${zone.lat.toStringAsFixed(3)}, ${zone.lng.toStringAsFixed(3)}',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.sensors),
              label: Text(
                zone.type == 'covered'
                    ? 'Browse nearby'
                    : multiplierText == kMultiplierUnavailable
                        ? 'Deploy sensor here'
                        : 'Deploy sensor here ($multiplierText WRF)',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
        'desert' => 'Data Desert — highest rewards',
        'sparse' => 'Sparse Coverage — elevated rewards',
        _ => 'Good Coverage',
      };
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── User location marker ──────────────────────────────────────────────────────

class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Legend ───────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend({required this.zones});
  final List<CoverageZone> zones;

  String _multiplierText(String type) {
    final m = zones
        .where((z) => z.type == type)
        .map((z) => z.rewardMultiplier)
        .whereType<double>()
        .firstOrNull;
    return formatRewardMultiplier(m);
  }

  String _label(String name, String type) {
    final text = _multiplierText(type);
    return text == kMultiplierUnavailable ? '$name ($text)' : '$name ($text WRF)';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(
            color: AppColors.error,
            label: _label('Data Desert', 'desert'),
          ),
          const SizedBox(height: 4),
          _LegendItem(
            color: AppColors.warning,
            label: _label('Sparse', 'sparse'),
          ),
          const SizedBox(height: 4),
          _LegendItem(
            color: AppColors.success,
            label: _label('Covered', 'covered'),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            border: Border.all(color: color),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class CoverageZone {
  const CoverageZone({
    required this.lat,
    required this.lng,
    required this.radius,
    required this.type,
    required this.color,
    this.rewardMultiplier,
  });

  final double lat;
  final double lng;
  final double radius;
  final String type;
  final Color color;
  final double? rewardMultiplier;

  static CoverageZone? fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final type = json['type']?.toString() ?? 'desert';
    final color = switch (type) {
      'covered' => AppColors.success,
      'sparse' => AppColors.warning,
      _ => AppColors.error,
    };

    return CoverageZone(
      lat: lat,
      lng: lng,
      radius: (json['radius'] as num?)?.toDouble() ?? 30,
      type: type,
      color: color,
      rewardMultiplier:
          (json['rewardMultiplier'] as num?)?.toDouble() ??
          (json['multiplier'] as num?)?.toDouble(),
    );
  }
}
