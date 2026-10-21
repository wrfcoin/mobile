import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feature_flags/feature_flags.dart';
import 'pws_discovery_service.dart';
import 'pws_station.dart';

/// Runs local-network PWS discovery when [FeatureFlags.enablePwsAutoDiscovery]
/// is on.  Returns an empty list while the flag is off (dark-launched).
///
/// In production the mDNS scan and HTTP probe implementations will be injected
/// via overrides; this scaffold uses no-op stubs so the flag can be exercised
/// in QA without real network hardware.
final pwsDiscoveryProvider = FutureProvider<List<PwsStation>>((ref) async {
  final flags = ref.watch(featureFlagsProvider);
  if (!flags.enablePwsAutoDiscovery) return const [];

  // Stub implementations — real platform code injected at app startup once
  // the feature ships.  Discovery is intentionally no-op until then.
  final service = PwsDiscoveryService(
    mdnsScan: (_) async => const [],
    httpProbe: (_, _) async => null,
  );
  return service.discover();
});
