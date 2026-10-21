import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final collectorPreferencesProvider = Provider<CollectorPreferences>((ref) {
  return const CollectorPreferences();
});

class CollectorPreferences {
  const CollectorPreferences();

  static const _isCollectingKey = 'collector.isCollecting';
  static const _intervalMinutesKey = 'collector.intervalMinutes';
  static const _batteryThresholdKey = 'collector.batteryThreshold';
  static const _syncedSubmissionCountKey = 'collector.syncedSubmissionCount';
  static const _rewardTotalsAvailableKey = 'collector.rewardTotalsAvailable';
  static const _earnedRewardWrfKey = 'collector.earnedRewardWrf';
  static const _lastSubmissionIdKey = 'collector.lastSubmissionId';
  static const _lastSubmissionStatusKey = 'collector.lastSubmissionStatus';
  static const _validationEventsKey = 'collector.validationEvents';
  static const _maxValidationEvents = 40;

  Future<CollectorPreferencesState> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CollectorPreferencesState(
      isCollecting: prefs.getBool(_isCollectingKey) ?? false,
      intervalMinutes: prefs.getInt(_intervalMinutesKey) ?? 15,
      batteryThreshold: prefs.getInt(_batteryThresholdKey) ?? 15,
      syncedSubmissionCount: prefs.getInt(_syncedSubmissionCountKey) ?? 0,
      rewardTotalsAvailable: prefs.getBool(_rewardTotalsAvailableKey) ?? false,
      earnedRewardWrf: prefs.getDouble(_earnedRewardWrfKey) ?? 0,
      lastSubmissionId: prefs.getString(_lastSubmissionIdKey),
      lastSubmissionStatus: prefs.getString(_lastSubmissionStatusKey),
    );
  }

  Future<void> save(CollectorPreferencesState state) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool(_isCollectingKey, state.isCollecting),
      prefs.setInt(_intervalMinutesKey, state.intervalMinutes),
      prefs.setInt(_batteryThresholdKey, state.batteryThreshold),
      prefs.setInt(_syncedSubmissionCountKey, state.syncedSubmissionCount),
      prefs.setBool(_rewardTotalsAvailableKey, state.rewardTotalsAvailable),
      prefs.setDouble(_earnedRewardWrfKey, state.earnedRewardWrf),
      _setNullableString(
        prefs,
        key: _lastSubmissionIdKey,
        value: state.lastSubmissionId,
      ),
      _setNullableString(
        prefs,
        key: _lastSubmissionStatusKey,
        value: state.lastSubmissionStatus,
      ),
    ]);
  }

  Future<void> _setNullableString(
    SharedPreferences prefs, {
    required String key,
    required String? value,
  }) {
    if (value == null || value.isEmpty) {
      return prefs.remove(key);
    }
    return prefs.setString(key, value);
  }

  Future<List<CollectorValidationEvent>> loadValidationEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final entries =
        prefs.getStringList(_validationEventsKey) ?? const <String>[];
    return entries
        .map((entry) {
          try {
            return CollectorValidationEvent.fromJson(
              jsonDecode(entry) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .nonNulls
        .toList(growable: false);
  }

  Future<void> appendValidationEvent(CollectorValidationEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final existing =
        prefs.getStringList(_validationEventsKey)?.toList() ?? <String>[];
    existing.insert(0, jsonEncode(event.toJson()));
    if (existing.length > _maxValidationEvents) {
      existing.removeRange(_maxValidationEvents, existing.length);
    }
    await prefs.setStringList(_validationEventsKey, existing);
  }

  Future<void> clearValidationEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_validationEventsKey);
  }
}

class CollectorPreferencesState {
  final bool isCollecting;
  final int intervalMinutes;
  final int batteryThreshold;
  final int syncedSubmissionCount;
  final bool rewardTotalsAvailable;
  final double earnedRewardWrf;
  final String? lastSubmissionId;
  final String? lastSubmissionStatus;

  const CollectorPreferencesState({
    required this.isCollecting,
    required this.intervalMinutes,
    required this.batteryThreshold,
    this.syncedSubmissionCount = 0,
    this.rewardTotalsAvailable = false,
    this.earnedRewardWrf = 0,
    this.lastSubmissionId,
    this.lastSubmissionStatus,
  });
}

class CollectorValidationEvent {
  final DateTime timestamp;
  final String code;
  final String message;

  const CollectorValidationEvent({
    required this.timestamp,
    required this.code,
    required this.message,
  });

  factory CollectorValidationEvent.fromJson(Map<String, dynamic> json) {
    return CollectorValidationEvent(
      timestamp: DateTime.parse(json['timestamp'] as String),
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'code': code,
      'message': message,
    };
  }
}
