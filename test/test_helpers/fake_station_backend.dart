import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registration_service.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/crypto/commit_id.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import 'fakes.dart';

// Synthetic key only (seed [7; 32]); it controls no real account.
const syntheticSeedHex =
    '0707070707070707070707070707070707070707070707070707070707070707';
const syntheticAddress = '0x791026e25cc1ba461167ffb5c6dc095c284bd92c';
const syntheticStationId = 'mob-7fe8d26b9fe9c060ea559732d5a6033e';

/// In-memory key store that counts reads per key, so a test can prove which
/// keys were (not) opened.
class CountingKeyValueStorage extends InMemoryKeyValueStorage {
  final Map<String, int> reads = <String, int>{};

  final Map<String, int> writes = <String, int>{};

  @override
  Future<String?> read({required String key}) {
    reads[key] = (reads[key] ?? 0) + 1;
    return super.read(key: key);
  }

  @override
  Future<void> write({required String key, String? value}) {
    writes[key] = (writes[key] ?? 0) + 1;
    return super.write(key: key, value: value);
  }

  /// Reads of the wallet's spending / login private key.
  int get walletKeyReads =>
      (reads['wrf_private_key'] ?? 0) + (reads['wrf_login_private_key'] ?? 0);
}

/// A deterministic collect key for [syntheticAddress] in a throwaway store.
Future<CollectKey> syntheticCollectKey({int seed = 1}) => CollectKeyStore(
  storage: InMemoryKeyValueStorage(),
  random: Random(seed),
).createFresh(syntheticAddress);

/// A collect-key store over an in-memory storage with a fixed random source.
CollectKeyStore syntheticCollectStore({
  KeyValueStorage? storage,
  int seed = 7,
}) => CollectKeyStore(
  storage: storage ?? CountingKeyValueStorage(),
  random: Random(seed),
);

/// Creates the phone's collect key in [store] and returns the SharedPreferences
/// entry that says "registered with this key" (what a completed v2
/// registration leaves behind).
Future<Map<String, Object>> registeredPrefsFor(CollectKeyStore store) async {
  final key = await store.createFresh(syntheticAddress);
  return <String, Object>{
    StationRegistrationService.registeredStationKey:
        StationRegistrationService.registrationMarker(
          syntheticStationId,
          key.publicKeyHex,
        ),
  };
}

/// Opens real [StationSigningSession]s over an in-memory key store and counts
/// how many times the (biometric-gated) key was read.
class SyntheticSigner {
  SyntheticSigner({this.biometricGranted = true, this.foreground = true});

  bool biometricGranted;
  bool foreground;
  int sessionsOpened = 0;
  int openAttempts = 0;

  final CountingKeyValueStorage storage = CountingKeyValueStorage();
  bool _stored = false;

  Future<StationSigningSession?> open() async {
    openAttempts++;
    if (!_stored) {
      await KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: storage,
      ).storeKeys(
        mnemonic: 'synthetic',
        privateKey: syntheticSeedHex,
        address: syntheticAddress,
      );
      _stored = true;
    }
    final km = KeyManager(
      biometric: BiometricService(
        client: FakeLocalAuthClient(authenticateResult: biometricGranted),
      ),
      storage: storage,
    );
    final session = await StationSigningService(
      keyManager: km,
      domain: TransferSigningDomain.configured,
      isForeground: () => foreground,
    ).openSession();
    if (session != null) sessionsOpened++;
    return session;
  }
}

class RecordedRequest {
  RecordedRequest(this.path, this.body);
  final String path;
  final Map<String, dynamic> body;
}

Uint8List _unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

/// A stand-in for the backend's challenge / register / prepare / submit routes
/// that really verifies the phone's signatures.
class FakeStationBackend {
  FakeStationBackend({this.nowSeconds = 1790683200});

  int nowSeconds;
  final List<RecordedRequest> requests = [];
  bool registered = false;
  // Separate GET corpus so existing submission-path assertions stay precise.
  final List<RequestOptions> statusRequests = [];
  int registrations = 0;

  /// The collect key the backend holds for the station (null = none pinned;
  /// tests that flip [registered] by hand accept any key).
  String? collectPubkey;

  /// Refuses every keyed commit, whatever key is pinned.
  bool forceCollectMismatch = false;

  /// Registrations that replaced an already-pinned, different collect key.
  int rotations = 0;

  /// Every registration signature that verified over preimage A v2.
  final List<String> verifiedRegistrationSignatures = [];

  // Fault injection.
  String? challengeStationId;
  String? challengeChainId;
  int? challengeExpiresIn;
  String? registerResponseStationId;
  String? prepareCommitId;
  String? prepareMessageHex;
  // Each overrides only that one echoed field, so the other cross-checks
  // cannot mask it.
  String? prepareStationId;
  int? prepareTimestamp;
  String? prepareAuthorizationCommitId;
  bool stickyNotOwned = false;
  int? failSubmitStatus;
  String? failSubmitCode;
  Map<String, String> failSubmitHeaders = const {};
  int? failRegisterStatus;

  final List<String> verifiedAuthSignatures = [];

  List<String> get paths => requests.map((r) => r.path).toList();
  int count(String suffix) => paths.where((p) => p.endsWith(suffix)).length;

  /// Records and answers one request; throws a [DioException] for an error.
  Future<Response<dynamic>> handle(RequestOptions options) {
    final body = options.data is Map
        ? Map<String, dynamic>.from(options.data as Map)
        : <String, dynamic>{};
    if (options.method == 'GET' && options.path == '/weather/stations/mobile') {
      statusRequests.add(options);
    } else {
      requests.add(RecordedRequest(options.path, body));
    }
    return _route(options, body);
  }

  Dio buildDio() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            handler.resolve(await handle(options));
          } on DioException catch (e) {
            handler.reject(e);
          }
        },
      ),
    );
    return dio;
  }

  Response<dynamic> _ok(
    RequestOptions o,
    Map<String, dynamic> data, [
    int s = 200,
  ]) => Response<dynamic>(requestOptions: o, statusCode: s, data: data);

  Never _fail(
    RequestOptions o,
    int status,
    String code, [
    Map<String, String> headers = const {},
  ]) {
    final response = Response<dynamic>(
      requestOptions: o,
      statusCode: status,
      data: <String, dynamic>{
        'success': false,
        'error': <String, dynamic>{'code': code, 'message': 'nope'},
      },
      headers: Headers.fromMap({
        for (final e in headers.entries) e.key: [e.value],
      }),
    );
    throw DioException.badResponse(
      statusCode: status,
      requestOptions: o,
      response: response,
    );
  }

  Future<Response<dynamic>> _route(
    RequestOptions o,
    Map<String, dynamic> body,
  ) async {
    switch (o.path) {
      case '/weather/stations/mobile/challenge':
        return _ok(o, {
          'success': true,
          'nonce': 'challenge-nonce-${requests.length}-0000',
          'expiresAt': nowSeconds + (challengeExpiresIn ?? 300),
          'stationId': challengeStationId ?? syntheticStationId,
          'ownerAddress': syntheticAddress,
          'chainId': challengeChainId ?? '888',
          'networkId': 'testnet',
        });
      case '/weather/stations/mobile':
        if (o.method == 'GET') {
          return _ok(o, {
            'stationId': syntheticStationId,
            'status': 'on_chain',
          });
        }
        if (failRegisterStatus != null) {
          _fail(o, failRegisterStatus!, 'REG_FAIL');
        }
        await _checkRegistration(o, body);
        final created = !registered;
        registered = true;
        if (created) registrations++;
        return _ok(o, {
          'success': true,
          'stationId': registerResponseStationId ?? syntheticStationId,
          'status': 'db_only',
          'created': created,
        }, created ? 201 : 200);
      case '/oracle/submit-data/prepare':
        return _prepare(o, body);
      case '/oracle/submit-data':
        return await _submit(o, body);
    }
    _fail(o, 404, 'NOT_FOUND');
  }

  /// Verifies the wallet's preimage A v2 signature exactly as the backend does.
  Future<void> _checkRegistration(
    RequestOptions o,
    Map<String, dynamic> body,
  ) async {
    if (body['version'] != 2 || body['collectPubkey'] is! String) {
      _fail(o, 400, 'REGISTRATION_VERSION_UNSUPPORTED');
    }
    final collect = (body['collectPubkey'] as String).toLowerCase();
    final cell = body['cell'] as Map;
    final message = mobileStationRegistrationMessage(
      chainId: '888',
      networkId: 'testnet',
      stationId: syntheticStationId,
      ownerAddress: syntheticAddress,
      collectPubkey: collect,
      latE1: cell['latE1'] as int,
      lonE1: cell['lonE1'] as int,
      nonce: body['nonce'] as String,
      expiresAt: body['expiresAt'] as int,
    );
    final valid = await Ed25519().verify(
      message,
      signature: Signature(
        _unhex(body['registrationSignature'] as String),
        publicKey: SimplePublicKey(
          _unhex(body['publicKey'] as String),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) _fail(o, 400, 'REGISTRATION_SIGNATURE_INVALID');
    if (collect == (body['publicKey'] as String).toLowerCase()) {
      _fail(o, 400, 'COLLECT_KEY_IS_WALLET_KEY');
    }
    verifiedRegistrationSignatures.add(body['registrationSignature'] as String);
    if (collectPubkey != null && collectPubkey != collect) rotations++;
    collectPubkey = collect;
  }

  /// 403 when the commit `auth_pubkey` is not the pinned collect key.
  void _checkCollectKey(RequestOptions o, Map<String, dynamic> body) {
    if (forceCollectMismatch && body['auth_pubkey'] is String) {
      _fail(o, 403, 'COLLECT_KEY_MISMATCH');
    }
    final pinned = collectPubkey;
    final supplied = body['auth_pubkey'];
    if (pinned != null && supplied is String && supplied != pinned) {
      _fail(o, 403, 'COLLECT_KEY_MISMATCH');
    }
  }

  String _localCommitId(Map<String, dynamic> body, String nonce) {
    final ts =
        DateTime.parse(body['timestamp'] as String).millisecondsSinceEpoch ~/
        1000;
    return computeCollectCommitId(
      pressureHpa: (body['value'] as num).toDouble(),
      nonce: nonce,
      stationId: (body['stationId'] ?? syntheticStationId) as String,
      timestampSeconds: ts,
    );
  }

  Response<dynamic> _prepare(RequestOptions o, Map<String, dynamic> body) {
    if (!registered || stickyNotOwned) _fail(o, 403, 'STATION_NOT_OWNED');
    _checkCollectKey(o, body);
    final nonce = body['nonce'] as String;
    final stationId = body['stationId'] as String;
    final commitId = prepareCommitId ?? _localCommitId(body, nonce);
    return _ok(o, {
      'success': true,
      'stationId': prepareStationId ?? stationId,
      'commitId': commitId,
      'nonce': nonce,
      'timestamp':
          prepareTimestamp ??
          DateTime.parse(body['timestamp'] as String).millisecondsSinceEpoch ~/
              1000,
      'authorization': {
        'scheme': 'wrfcoin_commit_auth_v2',
        'stationId': stationId,
        'commitId': prepareAuthorizationCommitId ?? commitId,
        'contributionType': 'contribution',
        'chainId': '888',
        'networkId': 'testnet',
        'messageHex': prepareMessageHex,
      },
    });
  }

  Future<Response<dynamic>> _submit(
    RequestOptions o,
    Map<String, dynamic> body,
  ) async {
    if (!registered || stickyNotOwned) _fail(o, 403, 'STATION_NOT_OWNED');
    _checkCollectKey(o, body);
    if (failSubmitStatus != null) {
      _fail(o, failSubmitStatus!, failSubmitCode ?? 'X', failSubmitHeaders);
    }
    final commitId = _localCommitId(body, body['nonce'] as String);
    final message = commitAuthorizationMessage(
      chainId: '888',
      networkId: 'testnet',
      stationId: body['stationId'] as String,
      commitId: commitId,
      contributionType: 'contribution',
    );
    final valid = await Ed25519().verify(
      message,
      signature: Signature(
        _unhex(body['auth_signature'] as String),
        publicKey: SimplePublicKey(
          _unhex(body['auth_pubkey'] as String),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) _fail(o, 502, 'BAD_AUTH');
    verifiedAuthSignatures.add(body['auth_signature'] as String);
    return _ok(o, {
      'success': true,
      'submissionId': commitId,
      'commitHash': commitId,
      'status': 'revealed_pending_attestation',
      'stationId': body['stationId'],
    });
  }
}

/// Answers a `prepare` request the way the real backend does, for tests that
/// only care about the submit leg. Returns null for any other request.
Response<dynamic>? answerPrepare(RequestOptions o) {
  if (o.path != '/oracle/submit-data/prepare') return null;
  final body = Map<String, dynamic>.from(o.data as Map);
  final nonce = body['nonce'] as String;
  final stationId = body['stationId'] as String;
  final timestamp =
      DateTime.parse(body['timestamp'] as String).millisecondsSinceEpoch ~/
      1000;
  final commitId = computeCollectCommitId(
    pressureHpa: (body['value'] as num).toDouble(),
    nonce: nonce,
    stationId: stationId,
    timestampSeconds: timestamp,
  );
  return Response<dynamic>(
    requestOptions: o,
    statusCode: 200,
    data: <String, dynamic>{
      'success': true,
      'stationId': stationId,
      'commitId': commitId,
      'nonce': nonce,
      'timestamp': timestamp,
      'authorization': <String, dynamic>{
        'contributionType': 'contribution',
        'stationId': stationId,
        'commitId': commitId,
        'messageHex': null,
      },
    },
  );
}
