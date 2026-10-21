// mobile#374 review round: the session is re-checked after the location wait (P2-2), and the read
// has no automatic retry and is cancelled on background, sign-out and dispose (P2-3), tested
// through the REAL KeyManager and the production ApiClient interceptors.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/station_temperature_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../../test_helpers/fakes.dart';
import 'temperature_test_completion.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter({this.status = 200, this.hold});
  final int status;
  final Completer<void>? hold;
  final List<String> requests = [];
  final List<String?> authorization = [];
  final started = Completer<void>();

  static final _body = jsonEncode({
    'daily': [
      {'date': '2026-09-29', 'minC': 10, 'maxC': 16, 'meanC': 12.0},
      {'date': '2026-09-30', 'minC': 12, 'maxC': 19, 'meanC': 14.0},
    ],
  });

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options.path);
    authorization.add(options.headers['Authorization'] as String?);
    if (!started.isCompleted) started.complete();
    if (hold != null) await hold!.future;
    // Public fake transport latency exposes the old 60 ms assumption.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return ResponseBody.fromString(status == 200 ? _body : '{}', status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

class _HeldResolver extends FixedWeatherLocationResolver {
  _HeldResolver(super.location, this.release);
  final Completer<void> release;
  int calls = 0;
  final started = Completer<void>();
  @override
  Future<WeatherLocationResult> resolve() async {
    calls++;
    if (!started.isCompleted) started.complete();
    await release.future;
    return super.resolve();
  }
}

Future<void> _settle(ProviderContainer c) => temperatureLoad(c);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KeyManager keys;
  late AuthHandoffController handoff;
  final now = DateTime.utc(2026, 10, 1, 15);

  setUp(() async {
    keys = KeyManager(biometric: BiometricService(client: FakeLocalAuthClient()), storage: InMemoryKeyValueStorage());
    await keys.storeAuthSession(jwt: 'jwt-token', expiresInSeconds: 3600);
    handoff = AuthHandoffController();
  });

  ProviderContainer make(_Adapter adapter, WeatherLocationResolver resolver) {
    final client = ApiClient(keyManager: keys, authHandoff: handoff);
    client.dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        stationTemperatureProvider.overrideWith(TrackedTemperatureNotifier.new),
        apiClientProvider.overrideWithValue(client),
        keyManagerProvider.overrideWithValue(keys),
        authHandoffControllerProvider.overrideWith((ref) => handoff),
        weatherLocationResolverProvider.overrideWithValue(resolver),
        weatherNarrativesClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    container.listen(stationTemperatureProvider, (_, _) {});
    return container;
  }

  final cell = CoarseLocation.round(44.98, -93.27);

  group('P2-2 the session is re-checked after the location wait', () {
    test('control: signed in, the read is sent with the session and produces narratives', () async {
      final adapter = _Adapter();
      final c = make(adapter, FixedWeatherLocationResolver(cell));
      await _settle(c);
      expect(adapter.requests, ['/weather/temperature-history']);
      expect(adapter.authorization.single, 'Bearer jwt-token');
      expect(c.read(stationTemperatureProvider).status, StationTemperatureStatus.ready);
    });

    test('sign-out (session cleared) while the location resolves: NO request is sent', () async {
      final adapter = _Adapter();
      final release = Completer<void>();
      final resolver = _HeldResolver(cell, release);
      final c = make(adapter, resolver);
      await resolver.started.future.timeout(const Duration(seconds: 10));
      expect(resolver.calls, 1);
      await keys.clearAccessToken();
      release.complete();
      await _settle(c);
      expect(adapter.requests, isEmpty, reason: 'no temperature, nonce or login request while signed out');
      expect(c.read(stationTemperatureProvider).status, StationTemperatureStatus.hidden);
    });

    test('a handoff (expiry, rejection) raised while the location resolves: NO request is sent', () async {
      final adapter = _Adapter();
      final release = Completer<void>();
      final resolver = _HeldResolver(cell, release);
      final c = make(adapter, resolver);
      await resolver.started.future.timeout(const Duration(seconds: 10));
      handoff.requireWalletConnect(reason: AuthHandoffReason.sessionExpired, message: 'Session expired.');
      release.complete();
      await _settle(c);
      expect(adapter.requests, isEmpty);
      expect(c.read(stationTemperatureProvider).status, StationTemperatureStatus.hidden);
    });
  });

  group('P2-3 lifecycle and session bound the read; no automatic retry', () {
    test('a 503 is tried once: the shared client does not retry it after about a second', () async {
      final adapter = _Adapter(status: 503);
      final c = make(adapter, FixedWeatherLocationResolver(cell));
      await _settle(c);
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(adapter.requests, hasLength(1));
      expect(c.read(stationTemperatureProvider).status, StationTemperatureStatus.unavailable);
    });

    test('a persistent 501 is tried once and hides the section quietly', () async {
      final adapter = _Adapter(status: 501);
      final c = make(adapter, FixedWeatherLocationResolver(cell));
      await _settle(c);
      await Future<void>.delayed(const Duration(milliseconds: 3300)); // past both retry delays
      expect(adapter.requests, hasLength(1));
      expect(c.read(stationTemperatureProvider).status, StationTemperatureStatus.hidden);
    });

    test('disposing the provider while a 503 is pending sends no second request', () async {
      final hold = Completer<void>();
      final adapter = _Adapter(status: 503, hold: hold);
      final c = make(adapter, FixedWeatherLocationResolver(cell));
      final completed = temperatureLoad(c);
      await adapter.started.future.timeout(const Duration(seconds: 10));
      c.dispose();
      hold.complete();
      await completed;
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(adapter.requests, hasLength(1));
    });

    test('backgrounding while the read is in flight discards its answer (and sends nothing more)', () async {
      final hold = Completer<void>();
      final adapter = _Adapter(hold: hold);
      final c = make(adapter, FixedWeatherLocationResolver(cell));
      await adapter.started.future.timeout(const Duration(seconds: 10));
      expect(adapter.requests, hasLength(1)); // in flight
      WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      hold.complete();
      await _settle(c);
      WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(adapter.requests, hasLength(1));
      expect(c.read(stationTemperatureProvider).status, isNot(StationTemperatureStatus.ready));
    });

    test('signing out while the read is in flight discards its answer and hides the section', () async {
      final hold = Completer<void>();
      final adapter = _Adapter(hold: hold);
      final c = make(adapter, FixedWeatherLocationResolver(cell));
      await adapter.started.future.timeout(const Duration(seconds: 10));
      expect(adapter.requests, hasLength(1));
      await keys.clearAccessToken();
      handoff.requireWalletConnect(reason: AuthHandoffReason.sessionExpired, message: 'Session expired.');
      hold.complete();
      await _settle(c);
      expect(c.read(stationTemperatureProvider).status, StationTemperatureStatus.hidden);
    });
  });
}
