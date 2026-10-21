import 'dart:async';

import 'pws_station.dart';

/// Signature for an mDNS scan. Returns stations advertising `_ecowitt._tcp.local`.
typedef MdnsScanFn = Future<List<PwsStation>> Function(Duration timeout);

/// Signature for an HTTP probe against a candidate IP. Returns a station on
/// success, null if the host is not a recognised PWS.
typedef HttpProbeFn = Future<PwsStation?> Function(
  String host,
  Duration timeout,
);

/// Discovers Ecowitt and Davis personal weather stations on the local network.
///
/// Feature-flagged via `enablePwsAutoDiscovery` (default off). Dark-launched:
/// discovered stations are surfaced for manual confirmation but never
/// auto-connected.
class PwsDiscoveryService {
  PwsDiscoveryService({
    required this._mdnsScan,
    required this._httpProbe,
    this._davisCandidateHosts = const <String>[],
    this._scanTimeout = const Duration(seconds: 3),
  });

  final MdnsScanFn _mdnsScan;
  final HttpProbeFn _httpProbe;
  final List<String> _davisCandidateHosts;
  final Duration _scanTimeout;

  /// Runs both discovery strategies in parallel and returns the union of
  /// stations found. Failures in one strategy never fail the overall scan.
  Future<List<PwsStation>> discover() async {
    final results = await Future.wait<List<PwsStation>>([
      _safeMdns(),
      _safeProbes(),
    ]);
    final seen = <String>{};
    final combined = <PwsStation>[];
    for (final batch in results) {
      for (final station in batch) {
        final key = '${station.host}:${station.port}';
        if (seen.add(key)) combined.add(station);
      }
    }
    return combined;
  }

  Future<List<PwsStation>> _safeMdns() async {
    try {
      return await _mdnsScan(_scanTimeout);
    } catch (_) {
      return const <PwsStation>[];
    }
  }

  Future<List<PwsStation>> _safeProbes() async {
    if (_davisCandidateHosts.isEmpty) return const <PwsStation>[];
    final probes = _davisCandidateHosts.map(
      (host) => _safeProbe(host, _scanTimeout),
    );
    final stations = await Future.wait(probes);
    return stations.whereType<PwsStation>().toList(growable: false);
  }

  Future<PwsStation?> _safeProbe(String host, Duration timeout) async {
    try {
      return await _httpProbe(host, timeout);
    } catch (_) {
      return null;
    }
  }
}
