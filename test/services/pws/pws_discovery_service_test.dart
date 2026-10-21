import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/pws/pws_discovery_service.dart';
import 'package:wrfcoin_mobile/services/pws/pws_station.dart';

void main() {
  group('PwsDiscoveryService', () {
    test('returns union of mDNS and HTTP probe results', () async {
      const ecowitt = PwsStation(
        brand: PwsBrand.ecowitt,
        name: 'GW2000A',
        host: '192.168.1.50',
        port: 80,
      );
      const davis = PwsStation(
        brand: PwsBrand.davis,
        name: 'WeatherLink',
        host: '192.168.1.60',
        port: 80,
      );

      final service = PwsDiscoveryService(
        mdnsScan: (_) async => const [ecowitt],
        httpProbe: (host, _) async => host == '192.168.1.60' ? davis : null,
        davisCandidateHosts: const ['192.168.1.60', '192.168.1.61'],
      );

      final stations = await service.discover();
      expect(stations, hasLength(2));
      expect(stations, contains(ecowitt));
      expect(stations, contains(davis));
    });

    test('returns empty list when no stations respond', () async {
      final service = PwsDiscoveryService(
        mdnsScan: (_) async => const [],
        httpProbe: (_, _) async => null,
        davisCandidateHosts: const ['192.168.1.60'],
      );

      final stations = await service.discover();
      expect(stations, isEmpty);
    });

    test('mDNS failure does not abort HTTP probe results', () async {
      const davis = PwsStation(
        brand: PwsBrand.davis,
        name: 'WeatherLink',
        host: '192.168.1.60',
        port: 80,
      );

      final service = PwsDiscoveryService(
        mdnsScan: (_) async => throw Exception('no multicast'),
        httpProbe: (_, _) async => davis,
        davisCandidateHosts: const ['192.168.1.60'],
      );

      final stations = await service.discover();
      expect(stations, [davis]);
    });

    test('HTTP probe timeout does not abort mDNS results', () async {
      const ecowitt = PwsStation(
        brand: PwsBrand.ecowitt,
        name: 'GW2000A',
        host: '192.168.1.50',
        port: 80,
      );

      final service = PwsDiscoveryService(
        mdnsScan: (_) async => const [ecowitt],
        httpProbe: (_, _) async => throw Exception('timeout'),
        davisCandidateHosts: const ['192.168.1.60'],
      );

      final stations = await service.discover();
      expect(stations, [ecowitt]);
    });

    test('deduplicates stations by host:port', () async {
      const dup = PwsStation(
        brand: PwsBrand.ecowitt,
        name: 'Same',
        host: '192.168.1.50',
        port: 80,
      );

      final service = PwsDiscoveryService(
        mdnsScan: (_) async => const [dup],
        httpProbe: (_, _) async => dup,
        davisCandidateHosts: const ['192.168.1.50'],
      );

      final stations = await service.discover();
      expect(stations, hasLength(1));
    });

    test('skips HTTP probe when no candidate hosts configured', () async {
      var probeCalls = 0;
      final service = PwsDiscoveryService(
        mdnsScan: (_) async => const [],
        httpProbe: (_, _) async {
          probeCalls += 1;
          return null;
        },
      );

      await service.discover();
      expect(probeCalls, 0);
    });
  });

  group('PwsStation', () {
    test('equality and hashCode respect all fields', () {
      const a = PwsStation(
        brand: PwsBrand.ecowitt,
        name: 'GW2000A',
        host: '192.168.1.50',
        port: 80,
      );
      const b = PwsStation(
        brand: PwsBrand.ecowitt,
        name: 'GW2000A',
        host: '192.168.1.50',
        port: 80,
      );
      const c = PwsStation(
        brand: PwsBrand.davis,
        name: 'GW2000A',
        host: '192.168.1.50',
        port: 80,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
