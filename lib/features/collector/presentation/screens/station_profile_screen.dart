import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/station_profile_provider.dart';
import '../widgets/uptime_badge.dart';
import '../widgets/sparkline_chart.dart';
import '../widgets/share_card.dart';

/// Full-screen station profile page with live data, impact stats,
/// uptime heatmap, and shareable station card.
class StationProfileScreen extends ConsumerWidget {
  final String stationId;

  const StationProfileScreen({super.key, required this.stationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(stationProfileProvider(stationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Station Profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Failed to load station profile',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.invalidate(stationProfileProvider(stationId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (profile) => _ProfileBody(profile: profile),
      ),
    );
  }
}

class _ProfileBody extends StatefulWidget {
  final StationProfile profile;

  const _ProfileBody({required this.profile});

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  final GlobalKey _shareCardKey = GlobalKey();

  StationProfile get profile => widget.profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Hero section
        _buildHeroSection(context),
        const SizedBox(height: 20),

        // Live data panel
        _buildLiveDataPanel(context),
        const SizedBox(height: 20),

        // Impact section
        _buildImpactSection(context),
        const SizedBox(height: 20),

        // Uptime heatmap
        _buildUptimeHeatmap(context),
        const SizedBox(height: 20),

        // Share section (hidden card + button)
        _buildShareSection(context),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    final isOnline = profile.status == 'online';
    final memberSinceText = DateFormat('MMM yyyy').format(profile.memberSince);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                // Status pulse indicator
                _PulseIndicator(isOnline: isOnline),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.model,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                UptimeBadge(uptimePercent: profile.uptimePercent),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _HeroStat(
                  icon: Icons.calendar_today,
                  label: 'Member since',
                  value: memberSinceText,
                ),
                _HeroStat(
                  icon: Icons.bar_chart,
                  label: 'Total readings',
                  value: _formatCount(profile.totalReadings),
                ),
                _HeroStat(
                  icon: Icons.circle,
                  label: 'Status',
                  value: isOnline ? 'Online' : 'Offline',
                  valueColor: isOnline ? AppColors.success : AppColors.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveDataPanel(BuildContext context) {
    final readings = profile.recentReadings;
    final temps = readings.map((r) => r.temperature).toList();
    final humidities = readings.map((r) => r.humidity.toDouble()).toList();
    final pressures = readings.map((r) => r.pressure).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Live Conditions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Last 4 hours with 24h rolling min/max/avg',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Temperature
            _LiveMetricRow(
              icon: Icons.thermostat,
              label: 'Temperature',
              currentValue: readings.isNotEmpty
                  ? '${readings.last.temperature.toStringAsFixed(1)}°C'
                  : '--',
              min: '${profile.tempMin24h.toStringAsFixed(1)}°',
              max: '${profile.tempMax24h.toStringAsFixed(1)}°',
              avg: '${profile.tempAvg24h.toStringAsFixed(1)}°',
              sparkData: temps,
              sparkColor: const Color(0xFFFF6B6B),
            ),
            const SizedBox(height: 16),

            // Humidity
            _LiveMetricRow(
              icon: Icons.water_drop,
              label: 'Humidity',
              currentValue: readings.isNotEmpty
                  ? '${readings.last.humidity}%'
                  : '--',
              min: '${profile.humidityMin24h.toStringAsFixed(0)}%',
              max: '${profile.humidityMax24h.toStringAsFixed(0)}%',
              avg: '${profile.humidityAvg24h.toStringAsFixed(0)}%',
              sparkData: humidities,
              sparkColor: const Color(0xFF339AF0),
            ),
            const SizedBox(height: 16),

            // Pressure
            _LiveMetricRow(
              icon: Icons.speed,
              label: 'Pressure',
              currentValue: readings.isNotEmpty
                  ? '${readings.last.pressure.toStringAsFixed(1)} hPa'
                  : '--',
              min: profile.pressureMin24h.toStringAsFixed(0),
              max: profile.pressureMax24h.toStringAsFixed(0),
              avg: '${profile.pressureAvg24h.toStringAsFixed(0)} hPa',
              sparkData: pressures,
              sparkColor: AppColors.secondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImpactSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Network Impact',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ImpactTile(
              icon: Icons.cloud_done,
              title:
                  'Contributed to ${_formatCount(profile.forecastContributions)} forecasts',
              subtitle:
                  'Your data helps improve weather predictions for everyone',
            ),
            const SizedBox(height: 12),
            _ImpactTile(
              icon: Icons.radar,
              title:
                  'Covers ${profile.coverageRadiusKm.toStringAsFixed(1)} km data gap',
              subtitle: 'Your station fills a crucial coverage area',
            ),
            const SizedBox(height: 12),
            _ImpactTile(
              icon: Icons.emoji_events,
              title: 'Top ${profile.contributorPercentile}% of contributors',
              subtitle: 'Based on data quality and uptime reliability',
              highlight: profile.contributorPercentile <= 10,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUptimeHeatmap(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Uptime History',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Daily reading activity over the past year',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _UptimeHeatmapGrid(heatmap: profile.uptimeHeatmap),
            const SizedBox(height: 8),
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  'Less',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 4),
                ...[0.0, 0.25, 0.5, 0.75, 1.0].map((level) {
                  return Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: _heatmapColor(level),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
                const SizedBox(width: 4),
                const Text(
                  'More',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareSection(BuildContext context) {
    return Column(
      children: [
        // The share card is rendered offscreen for capture
        Offstage(
          child: ShareCard(profile: profile, repaintKey: _shareCardKey),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Share Station Card'),
            onPressed: () => ShareCardHelper.shareStationCard(_shareCardKey),
          ),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

// -- Helper widgets --

class _PulseIndicator extends StatefulWidget {
  final bool isOnline;

  const _PulseIndicator({required this.isOnline});

  @override
  State<_PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<_PulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.isOnline) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isOnline ? AppColors.success : AppColors.error;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: widget.isOnline
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5 * _animation.value),
                      blurRadius: 8 * _animation.value,
                      spreadRadius: 2 * _animation.value,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _LiveMetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String currentValue;
  final String min;
  final String max;
  final String avg;
  final List<double> sparkData;
  final Color sparkColor;

  const _LiveMetricRow({
    required this.icon,
    required this.label,
    required this.currentValue,
    required this.min,
    required this.max,
    required this.avg,
    required this.sparkData,
    required this.sparkColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: sparkColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const Spacer(),
            Text(
              currentValue,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: sparkColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SparklineChart(values: sparkData, color: sparkColor, height: 40),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Min: $min',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            Text(
              'Avg: $avg',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            Text(
              'Max: $max',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ImpactTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlight;

  const _ImpactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surfaceLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: highlight
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
            color: highlight ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: highlight ? AppColors.primary : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// GitHub-style contribution heatmap for station uptime.
class _UptimeHeatmapGrid extends StatelessWidget {
  final Map<int, int> heatmap;

  const _UptimeHeatmapGrid({required this.heatmap});

  @override
  Widget build(BuildContext context) {
    // Show last ~52 weeks as a grid: 7 rows (days) x ~52 cols (weeks)
    const weeks = 52;
    const days = 7;
    final now = DateTime.now();

    return SizedBox(
      height: days * 12.0 + (days - 1) * 2.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: weeks,
        separatorBuilder: (_, _) => const SizedBox(width: 2),
        itemBuilder: (context, weekIndex) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(days, (dayIndex) {
              final daysAgo =
                  (weeks - 1 - weekIndex) * 7 + (days - 1 - dayIndex);
              final date = now.subtract(Duration(days: daysAgo));
              final dayOfYear = date.difference(DateTime(date.year)).inDays;
              final readings = heatmap[dayOfYear] ?? 0;
              final intensity = (readings / 48).clamp(0.0, 1.0);

              return Container(
                width: 10,
                height: 10,
                margin: dayIndex < days - 1
                    ? const EdgeInsets.only(bottom: 2)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: _heatmapColor(intensity),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

Color _heatmapColor(double intensity) {
  if (intensity <= 0) return AppColors.surfaceLight;
  if (intensity < 0.25) return AppColors.primary.withValues(alpha: 0.2);
  if (intensity < 0.5) return AppColors.primary.withValues(alpha: 0.4);
  if (intensity < 0.75) return AppColors.primary.withValues(alpha: 0.65);
  return AppColors.primary;
}
