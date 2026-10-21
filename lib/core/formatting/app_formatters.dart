import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../preferences/app_preferences.dart';

class AppFormatters {
  static Locale resolveLocale(
    BuildContext context,
    AppPreferences preferences,
  ) {
    return preferences.locale ??
        Localizations.maybeLocaleOf(context) ??
        WidgetsBinding.instance.platformDispatcher.locale;
  }

  static String formatTemperature(
    BuildContext context,
    AppPreferences preferences,
    double celsius, {
    int fractionDigits = 0,
  }) {
    final value = preferences.unitSystem == UnitSystem.imperial
        ? (celsius * 9 / 5) + 32
        : celsius;
    final unit = preferences.unitSystem == UnitSystem.imperial ? 'F' : 'C';
    return '${value.toStringAsFixed(fractionDigits)}°$unit';
  }

  static String formatPressure(
    BuildContext context,
    AppPreferences preferences,
    double pressureHpa, {
    int fractionDigits = 1,
  }) {
    if (preferences.unitSystem == UnitSystem.imperial) {
      final inHg = pressureHpa * 0.0295299830714;
      return '${inHg.toStringAsFixed(2)} inHg';
    }
    return '${pressureHpa.toStringAsFixed(fractionDigits)} hPa';
  }

  static String formatWindSpeed(
    BuildContext context,
    AppPreferences preferences,
    double speedKmh,
  ) {
    if (preferences.unitSystem == UnitSystem.imperial) {
      final mph = speedKmh * 0.621371;
      return '${mph.round()} mph';
    }
    return '${speedKmh.round()} km/h';
  }

  static String formatPrecipitation(
    BuildContext context,
    AppPreferences preferences,
    double precipitationMm,
  ) {
    if (preferences.unitSystem == UnitSystem.imperial) {
      final inches = precipitationMm / 25.4;
      return '${inches.toStringAsFixed(2)} in';
    }
    return '${precipitationMm.toStringAsFixed(1)} mm';
  }

  static String formatDateTime(
    BuildContext context,
    AppPreferences preferences,
    DateTime value, {
    bool includeDate = true,
    bool includeTime = true,
  }) {
    final locale = resolveLocale(context, preferences).toLanguageTag();
    final zoned = preferences.timezonePreference == TimezonePreference.utc
        ? value.toUtc()
        : value.toLocal();

    final formatter = switch ((includeDate, includeTime)) {
      (true, true) => DateFormat.yMMMd(locale).add_jm(),
      (true, false) => DateFormat.yMMMd(locale),
      (false, true) => DateFormat.jm(locale),
      _ => DateFormat.yMMMd(locale),
    };

    final formatted = formatter.format(zoned);
    if (preferences.timezonePreference == TimezonePreference.utc &&
        includeTime) {
      return '$formatted UTC';
    }
    return formatted;
  }

  static String formatIsoTimestamp(
    BuildContext context,
    AppPreferences preferences,
    String raw,
  ) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return formatDateTime(context, preferences, parsed);
  }
}
