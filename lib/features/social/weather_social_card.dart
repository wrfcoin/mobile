import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../weather/data/models/forecast_model.dart';

typedef WeatherCardCapture = Future<Uint8List?> Function(GlobalKey repaintKey);
typedef WeatherCardShareLauncher = Future<void> Function(
  List<XFile> files, {
  String? text,
});

/// A branded, share-ready weather card that can export itself as a PNG and
/// open the system share sheet.
class WeatherSocialCard extends StatefulWidget {
  const WeatherSocialCard({
    super.key,
    required this.forecast,
    required this.weatherRewards,
    this.shareService,
  });

  final ForecastModel forecast;
  final String? weatherRewards;
  final WeatherSocialCardShareService? shareService;

  @override
  State<WeatherSocialCard> createState() => _WeatherSocialCardState();
}

class _WeatherSocialCardState extends State<WeatherSocialCard> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  WeatherSocialCardShareService get _shareService =>
      widget.shareService ?? WeatherSocialCardShareService();

  Future<void> _shareCard() async {
    if (_sharing) return;

    setState(() => _sharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await _shareService.shareCard(
        repaintKey: _cardKey,
        text: WeatherSocialCardShareService.buildShareText(
          forecast: widget.forecast,
          weatherRewards: widget.weatherRewards,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: _cardKey,
          child: _WeatherSocialCardSurface(
            forecast: widget.forecast,
            weatherRewards: widget.weatherRewards,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _sharing ? null : _shareCard,
          icon: _sharing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.ios_share),
          label: const Text('Share weather card'),
        ),
      ],
    );
  }
}

/// Captures the weather card as PNG bytes and shares them through the
/// platform share sheet.
class WeatherSocialCardShareService {
  WeatherSocialCardShareService({
    WeatherCardCapture? captureCard,
    WeatherCardShareLauncher? shareLauncher,
  }) : _captureCard = captureCard ?? _defaultCaptureCard,
       _shareLauncher = shareLauncher ?? _defaultShareLauncher;

  static const String defaultFileName = 'wrfcoin-weather-card.png';

  final WeatherCardCapture _captureCard;
  final WeatherCardShareLauncher _shareLauncher;

  Future<void> shareCard({
    required GlobalKey repaintKey,
    required String text,
    String fileName = defaultFileName,
  }) async {
    final bytes = await _captureCard(repaintKey);
    if (bytes == null || bytes.isEmpty) return;

    await _shareLauncher([
      XFile.fromData(bytes, mimeType: 'image/png', name: fileName),
    ], text: text);
  }

  Future<Uint8List?> captureCardAsPng(
    GlobalKey repaintKey, {
    double pixelRatio = 3.0,
  }) async {
    return _defaultCaptureCard(repaintKey, pixelRatio: pixelRatio);
  }

  static String buildShareText({
    required ForecastModel forecast,
    required String? weatherRewards,
  }) {
    final summary = _buildWeatherSummary(forecast);
    final earnings = weatherRewards == null
        ? 'Earned rewards: Not available.'
        : 'I\'ve earned $weatherRewards WRF with WRFCoin.';
    return 'Current weather in ${forecast.location}: $summary. $earnings';
  }

  static Future<void> _defaultShareLauncher(
    List<XFile> files, {
    String? text,
  }) async {
    await SharePlus.instance.share(ShareParams(files: files, text: text));
  }

  static Future<Uint8List?> _defaultCaptureCard(
    GlobalKey repaintKey, {
    double pixelRatio = 3.0,
  }) async {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  static String _buildWeatherSummary(ForecastModel forecast) {
    final parts = <String>[
      if (forecast.temperature != null)
        '${forecast.temperature!.toStringAsFixed(1)}°C',
      if (forecast.humidity != null) '${forecast.humidity!.round()}% humidity',
      if (forecast.pressure != null)
        '${forecast.pressure!.toStringAsFixed(0)} hPa',
      if (forecast.windSpeed != null)
        forecast.windDirection != null &&
                forecast.windDirection!.trim().isNotEmpty
            ? '${forecast.windSpeed!.toStringAsFixed(1)} m/s ${forecast.windDirection}'
            : '${forecast.windSpeed!.toStringAsFixed(1)} m/s wind',
    ];

    if (forecast.precipitation != null && forecast.precipitation! > 0) {
      parts.add('${forecast.precipitation!.toStringAsFixed(1)} mm rain');
    }

    return parts.join(' · ');
  }
}

class _WeatherSocialCardSurface extends StatelessWidget {
  const _WeatherSocialCardSurface({
    required this.forecast,
    required this.weatherRewards,
  });

  final ForecastModel forecast;
  final String? weatherRewards;

  @override
  Widget build(BuildContext context) {
    final updatedAt = DateTime.tryParse(forecast.timestamp)?.toLocal();
    final updatedLabel = updatedAt == null
        ? 'Live now'
        : DateFormat('MMM d, h:mm a').format(updatedAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1220), Color(0xFF111B2D), Color(0xFF173042)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.cloud,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'WRFCoin Social Weather',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.auto_graph, color: Colors.white70, size: 18),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            forecast.location,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            updatedLabel,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                forecast.temperature == null
                    ? '—'
                    : '${forecast.temperature!.toStringAsFixed(1)}°C',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 46,
                  height: 0.95,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.1,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MetricPill(
                      icon: Icons.water_drop,
                      label: 'Humidity',
                      value: forecast.humidity == null
                          ? '—'
                          : '${forecast.humidity!.round()}%',
                    ),
                    _MetricPill(
                      icon: Icons.air,
                      label: 'Wind',
                      value: forecast.windSpeed == null
                          ? '—'
                          : forecast.windDirection == null ||
                                forecast.windDirection!.trim().isEmpty
                          ? '${forecast.windSpeed!.toStringAsFixed(1)} m/s'
                          : '${forecast.windSpeed!.toStringAsFixed(1)} m/s ${forecast.windDirection}',
                    ),
                    _MetricPill(
                      icon: Icons.compress,
                      label: 'Pressure',
                      value: forecast.pressure == null
                          ? '—'
                          : '${forecast.pressure!.toStringAsFixed(0)} hPa',
                    ),
                    _MetricPill(
                      icon: Icons.grain,
                      label: 'Rain',
                      value: forecast.precipitation == null
                          ? '—'
                          : '${forecast.precipitation!.toStringAsFixed(1)} mm',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.success, AppColors.primary],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.currency_exchange,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Weather earnings',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        weatherRewards == null
                            ? 'Not available'
                            : '$weatherRewards WRF earned',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Shared from the WRFCoin decentralized weather network',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.white70),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
