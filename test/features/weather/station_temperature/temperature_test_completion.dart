import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/station_temperature_provider.dart';

/// Observe the production initial load, including hidden paths with no state
/// transition. A timeout bounds a broken test; elapsed time never signals success.
class TrackedTemperatureNotifier extends StationTemperatureNotifier {
  final _initialLoad = Completer<void>();

  Future<void> get initialLoad => _initialLoad.future;

  @override
  Future<void> load() async {
    try {
      await super.load();
      _initialLoad.complete();
    } catch (error, stack) {
      _initialLoad.completeError(error, stack);
      rethrow;
    }
  }
}

Future<void> temperatureLoad(ProviderContainer container) =>
    (container.read(stationTemperatureProvider.notifier)
            as TrackedTemperatureNotifier)
        .initialLoad
        .timeout(const Duration(seconds: 10));
