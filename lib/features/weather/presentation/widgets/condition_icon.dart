import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// An icon for NOAA's short forecast text.
class ConditionIcon extends StatelessWidget {
  final String? shortForecast;

  const ConditionIcon({super.key, required this.shortForecast});

  @override
  Widget build(BuildContext context) {
    final text = shortForecast?.toLowerCase() ?? '';
    final icon = switch (text) {
      _ when text.contains('thunder') => Icons.thunderstorm,
      _ when text.contains('snow') || text.contains('sleet') => Icons.ac_unit,
      _
          when text.contains('rain') ||
              text.contains('shower') ||
              text.contains('drizzle') =>
        Icons.grain,
      _ when text.contains('fog') || text.contains('haze') => Icons.blur_on,
      _ when text.contains('partly') => Icons.wb_cloudy,
      _ when text.contains('cloud') || text.contains('overcast') => Icons.cloud,
      _ when text.contains('sunny') || text.contains('clear') => Icons.wb_sunny,
      _ when text.contains('wind') || text.contains('breezy') => Icons.air,
      _ => Icons.help_outline,
    };
    return Icon(icon, size: 18, color: AppColors.primary);
  }
}
