import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../providers/alert_settings_provider.dart';

class AlertSettingsScreen extends ConsumerStatefulWidget {
  const AlertSettingsScreen({super.key});

  @override
  ConsumerState<AlertSettingsScreen> createState() =>
      _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends ConsumerState<AlertSettingsScreen> {
  AlertSettings? _persistedSettings;
  bool _saving = false;

  double _aqiThreshold = 100;
  double _tempMin = 0;
  double _tempMax = 40;
  bool _severeWeather = true;
  bool _airQuality = true;
  bool _wildfire = true;

  bool get _hasUnsavedChanges {
    final persisted = _persistedSettings;
    if (persisted == null) return false;

    return _aqiThreshold.round() != persisted.aqiThreshold.round() ||
        _tempMin.round() != persisted.tempMin.round() ||
        _tempMax.round() != persisted.tempMax.round() ||
        _severeWeather != persisted.severeWeather ||
        _airQuality != persisted.airQuality ||
        _wildfire != persisted.wildfire;
  }

  AlertSettings get _draftSettings => AlertSettings(
    aqiThreshold: _aqiThreshold,
    tempMin: _tempMin,
    tempMax: _tempMax,
    severeWeather: _severeWeather,
    airQuality: _airQuality,
    wildfire: _wildfire,
  );

  void _hydrate(AlertSettings settings) {
    final shouldResetDraft =
        _persistedSettings == null ||
        (_persistedSettings != settings && !_hasUnsavedChanges);

    _persistedSettings = settings;

    if (shouldResetDraft) {
      _aqiThreshold = settings.aqiThreshold;
      _tempMin = settings.tempMin;
      _tempMax = settings.tempMax;
      _severeWeather = settings.severeWeather;
      _airQuality = settings.airQuality;
      _wildfire = settings.wildfire;
    }
  }

  void _discardChanges() {
    final persisted = _persistedSettings;
    if (persisted == null) return;

    setState(() {
      _aqiThreshold = persisted.aqiThreshold;
      _tempMin = persisted.tempMin;
      _tempMax = persisted.tempMax;
      _severeWeather = persisted.severeWeather;
      _airQuality = persisted.airQuality;
      _wildfire = persisted.wildfire;
    });
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasUnsavedChanges) return true;
    return showConfirmDialog(
      context,
      title: 'Discard Changes?',
      message: 'You have unsaved alert settings. Leave without saving?',
      confirmLabel: 'Discard',
      cancelLabel: 'Stay',
    );
  }

  Future<void> _save() async {
    if (_tempMin >= _tempMax) {
      AppSnackbars.error(
        context,
        const ValidationFailure(
          'Minimum temperature must be lower than maximum temperature.',
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(alertSettingsProvider.notifier).save(_draftSettings);
      if (!mounted) return;
      AppSnackbars.success(
        context,
        'Alert settings saved',
        detail:
            'AQI ${_aqiThreshold.round()}, range ${_tempMin.round()}°C to ${_tempMax.round()}°C',
      );
      setState(() {
        _persistedSettings = _draftSettings;
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(alertSettingsProvider);

    return PopScope<void>(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardChanges() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: settingsAsync.when(
        loading: () => Scaffold(
          appBar: AppBar(title: const Text('Alert Settings')),
          body: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Loading saved alert settings...'),
              ],
            ),
          ),
        ),
        error: (error, _) => Scaffold(
          appBar: AppBar(title: const Text('Alert Settings')),
          body: AppErrorWidget.fromFailure(
            error is Failure ? error : ServerFailure(error.toString()),
            onRetry: () => ref.read(alertSettingsProvider.notifier).load(),
          ),
        ),
        data: (settings) {
          _hydrate(settings);

          return Scaffold(
            appBar: AppBar(title: const Text('Alert Settings')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Alert Types',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Alerts are delivered while the app is open.',
                        ),
                        SwitchListTile(
                          title: const Text('Severe Weather'),
                          subtitle: const Text('Storms, floods, tornadoes'),
                          value: _severeWeather,
                          onChanged: (value) =>
                              setState(() => _severeWeather = value),
                        ),
                        SwitchListTile(
                          title: const Text('Air Quality'),
                          subtitle: const Text('AQI exceeds threshold'),
                          value: _airQuality,
                          onChanged: (value) =>
                              setState(() => _airQuality = value),
                        ),
                        SwitchListTile(
                          title: const Text('Wildfire Risk'),
                          subtitle: const Text('Elevated fire danger'),
                          value: _wildfire,
                          onChanged: (value) =>
                              setState(() => _wildfire = value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AQI Alert Threshold: ${_aqiThreshold.round()}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Slider(
                          value: _aqiThreshold,
                          min: 50,
                          max: 300,
                          divisions: 25,
                          label: _aqiThreshold.round().toString(),
                          onChanged: _airQuality
                              ? (value) => setState(() => _aqiThreshold = value)
                              : null,
                        ),
                        const Text(
                          '0-50 Good | 51-100 Moderate | 101-150 Unhealthy (Sensitive) | 151+ Unhealthy',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Temperature Range',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RangeSlider(
                          values: RangeValues(_tempMin, _tempMax),
                          min: -40,
                          max: 60,
                          divisions: 100,
                          labels: RangeLabels(
                            '${_tempMin.round()}°C',
                            '${_tempMax.round()}°C',
                          ),
                          onChanged: (value) => setState(() {
                            _tempMin = value.start;
                            _tempMax = value.end;
                          }),
                        ),
                        Text(
                          'Alert when temperature is below ${_tempMin.round()}°C or above ${_tempMax.round()}°C',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 96),
              ],
            ),
            bottomNavigationBar: SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _hasUnsavedChanges && !_saving
                          ? _discardChanges
                          : null,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _hasUnsavedChanges && !_saving ? _save : null,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
