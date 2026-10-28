import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api/api_client.dart';

final shadowAlertsEnabledProvider = Provider<bool>(
  (ref) => const String.fromEnvironment('WRFCOIN_SHADOW_ALERTS') == 'on',
);
final shadowAlertsControllerProvider =
    Provider.autoDispose<ShadowAlertsController>((ref) {
      final controller = ShadowAlertsController((token) async {
        final api = ref.read(apiClientProvider);
        if (!await api.ensureWalletSession()) {
          throw StateError('Sign in required');
        }
        if (token.isCancelled) return [];
        final response = await api.dio.get(
          '/weather/alerts/shadow',
          cancelToken: token,
        );
        final body = response.data;
        if (body is! Map || body['shadow'] != true || body['events'] is! List) {
          throw const FormatException('Invalid research response');
        }
        return (body['events'] as List)
            .cast<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
      ref.onDispose(controller.dispose);
      return controller;
    });

typedef ShadowLoader = Future<List<Map<String, dynamic>>> Function(
  CancelToken token,
);

class ShadowAlertsController extends ChangeNotifier
    with WidgetsBindingObserver {
  ShadowAlertsController(
    this.loader, {
    this.interval = const Duration(minutes: 1),
  });
  final ShadowLoader loader;
  final Duration interval;
  String cell = '';
  Set<String> hazards = {'rain', 'heat', 'wind'};
  List<Map<String, dynamic>> events = [];
  String? error;
  bool loading = false;
  bool _disposed = false;
  bool _started = false;
  bool _foreground = false;
  Timer? _timer;
  CancelToken? _request;
  int _generation = 0;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    cell = prefs.getString('shadow_alerts.cell') ?? '';
    hazards =
        (prefs.getStringList('shadow_alerts.hazards') ??
                ['rain', 'heat', 'wind'])
            .toSet();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    notifyListeners();
    _schedule();
  }

  static bool validCell(String value) {
    if (!RegExp(r'^-?\d{1,3}\.\d,-?\d{1,3}\.\d$').hasMatch(value)) return false;
    final numbers = value.split(',').map(double.parse).toList();
    return numbers[0] >= -90 &&
        numbers[0] < 90 &&
        numbers[1] >= -180 &&
        numbers[1] < 180;
  }

  Future<void> save(String area, Set<String> selected) async {
    if (!validCell(area) ||
        selected.isEmpty ||
        selected.any((h) => !['rain', 'heat', 'wind'].contains(h))) {
      throw const FormatException('Use a coarse cell and select a hazard');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shadow_alerts.cell', area);
    await prefs.setStringList('shadow_alerts.hazards', selected.toList());
    if (_disposed) return;
    _cancel();
    cell = area;
    hazards = Set.of(selected);
    events = [];
    error = null;
    notifyListeners();
    _schedule();
  }

  void _cancel() {
    _generation++;
    _request?.cancel();
    _request = null;
    _timer?.cancel();
    _timer = null;
    loading = false;
  }

  void _schedule() {
    if (!_foreground || _disposed || !validCell(cell)) return;
    unawaited(poll());
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(poll()));
  }

  Future<void> poll() async {
    if (!_foreground || _disposed || loading || !validCell(cell)) return;
    final generation = _generation;
    final token = CancelToken();
    _request = token;
    loading = true;
    notifyListeners();
    try {
      final result = await loader(token);
      if (_disposed || !_foreground || generation != _generation) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      events = result
          .where(
            (e) =>
                e['shadow'] == true &&
                e['cell'] == cell &&
                hazards.contains(e['hazard']) &&
                e['expires'] is num &&
                (e['expires'] as num) > now &&
                e['at'] is num &&
                (e['at'] as num) <= now &&
                ['advisory', 'suppressed_by_official'].contains(e['status']),
          )
          .toList();
      error = null;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = 'Research alerts unavailable. Check the official service.';
        events = [];
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _cancel();
    if (!_foreground) events = [];
    if (!_disposed) notifyListeners();
    _schedule();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
