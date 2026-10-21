import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../providers/collector_provider.dart';

class SensorSettingsScreen extends ConsumerStatefulWidget {
  const SensorSettingsScreen({super.key});

  @override
  ConsumerState<SensorSettingsScreen> createState() =>
      _SensorSettingsScreenState();
}

class _SensorSettingsScreenState extends ConsumerState<SensorSettingsScreen> {
  int? _savedIntervalMinutes;
  int? _savedBatteryThreshold;
  int _intervalMinutes = 15;
  int _batteryThreshold = 15;
  bool _saving = false;

  bool get _hasUnsavedChanges {
    return _savedIntervalMinutes != null &&
        (_intervalMinutes != _savedIntervalMinutes ||
            _batteryThreshold != _savedBatteryThreshold);
  }

  void _hydrate(CollectorState state) {
    final shouldResetDraft =
        _savedIntervalMinutes == null || !_hasUnsavedChanges;
    _savedIntervalMinutes = state.intervalMinutes;
    _savedBatteryThreshold = state.batteryThreshold;

    if (shouldResetDraft) {
      _intervalMinutes = state.intervalMinutes;
      _batteryThreshold = state.batteryThreshold;
    }
  }

  void _discardChanges() {
    if (_savedIntervalMinutes == null || _savedBatteryThreshold == null) return;
    setState(() {
      _intervalMinutes = _savedIntervalMinutes!;
      _batteryThreshold = _savedBatteryThreshold!;
    });
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasUnsavedChanges) return true;
    return showConfirmDialog(
      context,
      title: 'Discard Changes?',
      message: 'You have unsaved sensor settings. Leave without saving?',
      confirmLabel: 'Discard',
      cancelLabel: 'Stay',
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(collectorProvider.notifier)
          .saveSettings(
            intervalMinutes: _intervalMinutes,
            batteryThreshold: _batteryThreshold,
          );
      if (!mounted) return;
      AppSnackbars.success(
        context,
        'Sensor settings saved',
        detail:
            'Collect every $_intervalMinutes min, pause below $_batteryThreshold%',
      );
      setState(() {
        _savedIntervalMinutes = _intervalMinutes;
        _savedBatteryThreshold = _batteryThreshold;
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectorProvider);
    _hydrate(state);

    return PopScope<void>(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardChanges() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Sensor Settings')),
        body: !state.settingsLoaded
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Loading saved sensor settings...'),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Collection Interval',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 5, label: Text('5 min')),
                              ButtonSegment(value: 15, label: Text('15 min')),
                              ButtonSegment(value: 30, label: Text('30 min')),
                            ],
                            selected: {_intervalMinutes},
                            onSelectionChanged: (selected) {
                              setState(() => _intervalMinutes = selected.first);
                            },
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
                            'Battery Threshold: $_batteryThreshold%',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Pause collection when battery drops below this level',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          Slider(
                            value: _batteryThreshold.toDouble(),
                            min: 5,
                            max: 30,
                            divisions: 5,
                            label: '$_batteryThreshold%',
                            onChanged: (value) {
                              setState(() => _batteryThreshold = value.round());
                            },
                          ),
                          if (_batteryThreshold < 10)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.warning.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber,
                                    color: AppColors.warning,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Low thresholds can drain battery faster during collection.',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
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
                            'GPS Privacy',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.shield,
                                color: AppColors.success,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Coordinates are rounded to ~11 km (0.1°) before storage and submission.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 96),
                ],
              ),
        bottomNavigationBar: state.settingsLoaded
            ? SafeArea(
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
                        onPressed: _hasUnsavedChanges && !_saving
                            ? _save
                            : null,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}
