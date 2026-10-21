import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/wrf_forecast_model.dart';
import 'wrf_forecast_chart.dart' show WrfSimulatedBadge;

/// Compact card showing today's accumulated HDD/CDD values and a tappable
/// chip with the IPFS content ID of the underlying WRF output file.
///
/// HDD is displayed in blue, CDD in orange, matching the conventional
/// energy-industry colour scheme.
class HddCddCard extends StatelessWidget {
  final WrfForecastModel forecast;

  const HddCddCard({super.key, required this.forecast});

  // Sum HDD/CDD across all hourly points for "today".
  double get _totalHdd {
    final today = DateTime.now().toUtc().day;
    return forecast.hourly
        .where((p) {
          final ts = DateTime.tryParse(p.timestamp);
          return ts != null && ts.toUtc().day == today;
        })
        .fold(0.0, (acc, p) => acc + p.hdd);
  }

  double get _totalCdd {
    final today = DateTime.now().toUtc().day;
    return forecast.hourly
        .where((p) {
          final ts = DateTime.tryParse(p.timestamp);
          return ts != null && ts.toUtc().day == today;
        })
        .fold(0.0, (acc, p) => acc + p.cdd);
  }

  @override
  Widget build(BuildContext context) {
    final hdd = _totalHdd;
    final cdd = _totalCdd;
    final total = hdd + cdd;
    final hddFraction = total > 0 ? hdd / total : 0.5;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Degree Days (base 18.3°C)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                WrfSimulatedBadge(isSimulated: forecast.isSimulated),
              ],
            ),
            const SizedBox(height: 12),

            // HDD / CDD value row.
            Row(
              children: [
                _DegreeDay(
                  label: 'HDD',
                  value: hdd,
                  color: Colors.blue,
                  semanticLabel:
                      'Heating degree days: ${hdd.toStringAsFixed(1)}',
                ),
                const SizedBox(width: 24),
                _DegreeDay(
                  label: 'CDD',
                  value: cdd,
                  color: Colors.orange,
                  semanticLabel:
                      'Cooling degree days: ${cdd.toStringAsFixed(1)}',
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Stacked bar — HDD blue / CDD orange.
            Semantics(
              label:
                  'Bar chart: heating ${hdd.toStringAsFixed(1)} degree days, '
                  'cooling ${cdd.toStringAsFixed(1)} degree days',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      Flexible(
                        flex: (hddFraction * 1000).round(),
                        child: Container(color: Colors.blue),
                      ),
                      Flexible(
                        flex: ((1 - hddFraction) * 1000).round(),
                        child: Container(color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // IPFS CID chip.
            _IpfsCidChip(cid: forecast.ipfsCid),
          ],
        ),
      ),
    );
  }
}

class _DegreeDay extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final String semanticLabel;

  const _DegreeDay({
    required this.label,
    required this.value,
    required this.color,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IpfsCidChip extends StatelessWidget {
  final String cid;

  const _IpfsCidChip({required this.cid});

  String get _shortCid {
    if (cid.length <= 16) return cid;
    return '${cid.substring(0, 8)}…${cid.substring(cid.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'IPFS source: $cid. Tap to copy.',
      child: Tooltip(
        message: 'IPFS CID: $cid\nTap to copy',
        preferBelow: false,
        child: GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: cid));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('IPFS CID copied to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: Chip(
            avatar: const Icon(
              Icons.cloud_queue,
              size: 14,
              color: AppColors.textSecondary,
            ),
            label: Text(
              _shortCid,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
            backgroundColor: AppColors.surfaceLight,
            side: const BorderSide(color: AppColors.border),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.only(right: 4),
          ),
        ),
      ),
    );
  }
}
