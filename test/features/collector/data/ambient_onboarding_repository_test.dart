import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/ambient_onboarding_repository.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';

import '../../../test_helpers/ambient_transport.dart';

class _SessionGate extends ApiClient {
  _SessionGate(AmbientTransport transport, this.session)
    : super(dio: transport.client().dio);
  final Future<bool> session;
  @override
  Future<bool> ensureWalletSession() => session;
}

void main() {
  late AmbientTransport transport;
  late AmbientOnboardingRepository repo;
  Future<VerifiedAmbientAccount> verify() =>
      repo.verify(apiKey: ' ${ambientKeys[0]} ', appKey: ambientKeys[1]);
  Future<String> register(
    VerifiedAmbientAccount account, {
    AmbientDevice? device,
    double lat = 12.3456,
    double lon = -45.6789,
    String name = ' Test station ',
  }) => repo.register(
    account: account,
    device: device ?? account.devices.first,
    name: name,
    latitude: lat,
    longitude: lon,
  );
  setUp(() {
    transport = AmbientTransport();
    repo = AmbientOnboardingRepository(transport.client());
  });

  test(
    'verified selection binds canonical MAC and keys to coarse registration',
    () async {
      final account = await verify();
      expect(account.devices.map((e) => e.label), [
        'Ambient station • ee01',
        'Ambient station • ee02',
      ]);
      expect(() => account.devices.clear(), throwsUnsupportedError);
      transport.payload = ambientReceipt;
      expect(
        await register(account, device: account.devices.last),
        'station_synthetic',
      );
      expect(transport.requests.map((e) => e.path), [
        '/weather/stations/verify-key',
        '/weather/stations',
      ]);
      expect(transport.requests.first.data, {
        'provider': 'ambient',
        'apiKey': ambientKeys[0],
        'appKey': ambientKeys[1],
      });
      expect(transport.requests.last.data, {
        'provider': 'ambient',
        'mac': 'aabbccddee02',
        'name': 'Test station',
        'latitude': 12.3,
        'longitude': -45.7,
        'ambientApiKey': ambientKeys[0],
        'ambientAppKey': ambientKeys[1],
      });
      for (final request in transport.requests) {
        expect(request.uri.host, 'backend.invalid');
        expect(request.method, 'POST');
        expect(request.followRedirects, isFalse);
        expect(request.extra['noRetry'], isTrue);
      }
    },
  );

  test('session refusal and cancellation prevent all HTTP', () async {
    repo = AmbientOnboardingRepository(transport.client(authenticated: false));
    await expectLater(verify(), throwsA(isA<AmbientOnboardingProblem>()));
    repo = AmbientOnboardingRepository(transport.client());
    await expectLater(
      repo.verify(
        apiKey: ambientKeys[0],
        appKey: ambientKeys[1],
        cancel: CancelToken()..cancel(),
      ),
      throwsA(isA<AmbientOnboardingProblem>()),
    );
    expect(transport.requests, isEmpty);
  });
  test('invalid credentials prevent HTTP', () async {
    for (final key in ['', ' ', 'a' * 513]) {
      await expectLater(
        repo.verify(apiKey: key, appKey: ambientKeys[1]),
        throwsA(isA<AmbientOnboardingProblem>()),
      );
      await expectLater(
        repo.verify(apiKey: ambientKeys[0], appKey: key),
        throwsA(isA<AmbientOnboardingProblem>()),
      );
    }
    expect(transport.requests, isEmpty);
  });
  test(
    'cancellation during session renewal prevents sending credentials',
    () async {
      final session = Completer<bool>();
      repo = AmbientOnboardingRepository(
        _SessionGate(transport, session.future),
      );
      final cancel = CancelToken();
      final request = repo.verify(
        apiKey: ambientKeys[0],
        appKey: ambientKeys[1],
        cancel: cancel,
      );
      final refused = expectLater(
        request,
        throwsA(isA<AmbientOnboardingProblem>()),
      );
      cancel.cancel();
      session.complete(true);
      await refused;
      expect(transport.requests, isEmpty);
    },
  );
  test(
    'empty verified account is honest and has no selectable device',
    () async {
      transport.payload = {'valid': true, 'devices': []};
      expect((await verify()).devices, isEmpty);
    },
  );
  final malformed = <Object?>[
    null,
    [],
    {'valid': 'true', 'devices': []},
    {'valid': false, 'devices': []},
    {'valid': true},
    {'valid': true, 'devices': 'wrong'},
    {
      'valid': true,
      'devices': List.filled(101, {'mac': 'aabbccddee01'}),
    },
    for (final mac in [
      null,
      12,
      'localhost',
      'aa:bb-cc:dd:ee:01',
      'aabbccddee01/',
    ])
      {
        'valid': true,
        'devices': [
          {'mac': mac},
        ],
      },
    {
      'valid': true,
      'devices': [
        {'mac': 'aabbccddee01'},
        {'mac': 'AA:BB:CC:DD:EE:01'},
      ],
    },
  ];
  for (var i = 0; i < malformed.length; i++) {
    test('malformed account response $i cannot authorize selection', () async {
      transport.payload = malformed[i];
      await expectLater(verify(), throwsA(isA<AmbientOnboardingProblem>()));
      expect(transport.requests, hasLength(1));
    });
  }
  test(
    'foreign account device and invalid location/name never register',
    () async {
      final account = await verify();
      final other = await verify();
      await expectLater(
        register(account, device: other.devices.first),
        throwsA(isA<AmbientOnboardingProblem>()),
      );
      for (final lat in [double.nan, double.infinity, 90.01, -90.01]) {
        await expectLater(
          register(account, lat: lat),
          throwsA(isA<AmbientOnboardingProblem>()),
        );
      }
      for (final lon in [double.nan, double.infinity, 180.01, -180.01]) {
        await expectLater(
          register(account, lon: lon),
          throwsA(isA<AmbientOnboardingProblem>()),
        );
      }
      for (final name in ['', ' ', 'a' * 81]) {
        await expectLater(
          register(account, name: name),
          throwsA(isA<AmbientOnboardingProblem>()),
        );
      }
      expect(transport.requests, hasLength(2));
    },
  );
  test(
    'registration needs explicit provider, success and safe station ID',
    () async {
      final account = await verify();
      for (final body in [
        {},
        {'success': true},
        {...ambientReceipt, 'success': false},
        {...ambientReceipt, 'provider': 'ecowitt'},
        for (final id in [null, 12, '', '../unsafe', 'a' * 65])
          {...ambientReceipt, 'stationId': id},
      ]) {
        transport.payload = body;
        await expectLater(
          register(account),
          throwsA(isA<AmbientOnboardingProblem>()),
        );
      }
    },
  );
  for (final status in [301, 401, 403, 404, 409, 422, 429, 501, 502]) {
    test(
      'HTTP $status yields a static error with no credential/body echo or retry',
      () async {
        transport.status = status;
        transport.payload = {'error': ambientKeys.join(' ')};
        try {
          await verify();
          fail('expected refusal');
        } on AmbientOnboardingProblem catch (error) {
          for (final key in ambientKeys) {
            expect(error.toString(), isNot(contains(key)));
          }
          expect(error.toString(), isNot(contains('backend.invalid')));
        }
        expect(transport.requests, hasLength(1));
      },
    );
  }
}
