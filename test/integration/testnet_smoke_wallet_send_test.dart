// Offline smoke: real app/router, biometric key read, repository, nonce and
// ed25519 signing. Only transport/session availability are controlled. This
// proves submission behavior, never live funding or chain inclusion.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';
import 'package:wrfcoin_mobile/core/feature_flags/build_flags.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../test_helpers/app_harness.dart';
import '../test_helpers/fakes.dart';

const _recipient = '0x2222222222222222222222222222222222222222';
const _displayAmount = '1.50000001';
const _baseAmount = '150000001';
final _submissionHash = 'ab' * 32;

void main() {
  Future<_Transport> enterSend(
    WidgetTester tester, {
    bool biometric = true,
    bool conflict = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'welcome.seen': true,
    });
    final signer = await Ed25519TransferSigner.fromSeedHex('07' * 32);
    final sender = WalletSetupService().chainAddressFromEd25519(
      signer.publicKey,
    );
    final storage = InMemoryKeyValueStorage();
    // A stored canonical wallet, rather than a create/import operation that
    // also modifies the process-wide login-attempt guard.
    await storage.write(key: 'wrf_private_key', value: '07' * 32);
    await storage.write(key: 'wrf_address', value: sender);
    await storage.write(
      key: 'wrf_key_scheme',
      value: KeyManager.canonicalKeyScheme,
    );
    final keys = KeyManager(
      biometric: BiometricService(
        client: FakeLocalAuthClient(authenticateResult: biometric),
      ),
      storage: storage,
    );
    final transport = _Transport(sender, signer.publicKey, conflict: conflict);
    final db = createTestDatabase();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(db.close);
    });
    addTearDown(() => transport.dio.close(force: true));
    final harness = await buildTestApp(db: db) as ProviderScope;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...harness.overrides.where(
            (entry) =>
                entry.origin != keyManagerProvider &&
                entry.origin != walletRepositoryProvider,
          ),
          walletSendEnabledProvider.overrideWithValue(true),
          keyManagerProvider.overrideWithValue(keys),
          // This synthetic session seam cannot log in or contact a live host.
          apiClientProvider.overrideWithValue(
            ApiClient(dio: transport.dio, allowUnauthenticatedRequests: true),
          ),
          walletRepositoryProvider.overrideWithValue(
            WalletRepositoryImpl(WalletRemoteDataSource(transport.dio)),
          ),
        ],
        child: harness.child,
      ),
    );
    await pumpFrames(tester);
    await pumpUntilFound(tester, find.text('Earnings'));
    await tester.tap(find.text('Earnings').last);
    await pumpUntilFound(tester, find.widgetWithText(ElevatedButton, 'Send'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await pumpUntilFound(tester, find.widgetWithText(TextFormField, 'Send to'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Send to'),
      _recipient,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (WRF)'),
      _displayAmount,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await pumpFrames(tester);
    return transport;
  }

  testWidgets(
    'wallet-send smoke confirms and signs exact base units and nonce',
    (tester) async {
      final transport = await enterSend(tester);
      expect(find.text('Confirm Send'), findsOneWidget);
      expect(
        transport.sends,
        isEmpty,
        reason: 'No send before user confirmation',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await pumpUntilFound(tester, find.text('Submission receipt'));
      expect(find.text(_submissionHash), findsOneWidget);
      expect(
        find.text('Submitted. Settlement has not been verified.'),
        findsOneWidget,
      );
      expect(find.text('Sent successfully'), findsNothing);
      // Fee on open, fee after the PIN, then the one read the signature uses.
      expect(transport.nonceReads, 3);
      expect(transport.sends, hasLength(1));
      expect(transport.sends.single.extra['noRetry'], true);
      final body = Map<String, dynamic>.from(
        transport.sends.single.data as Map,
      );
      expect(body.keys.toSet(), {
        'from',
        'to',
        'amount',
        'nonce',
        'auth_pubkey',
        'auth_signature',
      });
      expect(body['from'], transport.sender);
      expect(body['to'], _recipient);
      expect(body['amount'], _baseAmount);
      expect(body['nonce'], '42');
      expect(
        _hexBytes(body['auth_pubkey'] as String),
        orderedEquals(transport.publicKey),
      );
      // Independently frame the expected chain-888/testnet preimage, rather than
      // calling the production preimage builder and masking a domain mutation.
      expect(
        await Ed25519().verify(
          _expectedMessage(transport.sender),
          signature: Signature(
            _hexBytes(body['auth_signature'] as String),
            publicKey: SimplePublicKey(
              transport.publicKey,
              type: KeyPairType.ed25519,
            ),
          ),
        ),
        isTrue,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Done'));
      await pumpFrames(tester);
      expect(find.widgetWithText(TextFormField, 'Send to'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wallet-send smoke exposes pending conflict without retry or success',
    (tester) async {
      final transport = await enterSend(tester, conflict: true);
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await pumpUntilFound(
        tester,
        find.textContaining('Previous transfer still pending'),
      );
      await pumpFrames(tester, frames: 20);
      // Fee on open, fee after the PIN, then the one read the signature uses.
      expect(transport.nonceReads, 3);
      expect(transport.sends, hasLength(1));
      expect(find.text('Sent successfully'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Send to'), findsOneWidget);
      expect(find.text('Submission receipt'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wallet-send smoke cannot submit after biometric denial', (
    tester,
  ) async {
    final transport = await enterSend(tester, biometric: false);
    expect(find.text('Authentication required to send'), findsOneWidget);
    expect(find.text('Confirm Send'), findsNothing);
    // Only the fee read on open; nothing is signed, so no signing read.
    expect(transport.nonceReads, 1);
    expect(transport.sends, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

List<int> _hexBytes(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

List<int> _expectedMessage(String sender) {
  final bytes = <int>[...utf8.encode('wrfcoin_transparent_transfer_auth_v2')];
  for (final field in ['888', 'testnet', sender, _recipient]) {
    final text = utf8.encode(field);
    bytes.addAll(
      (ByteData(
        4,
      )..setUint32(0, text.length, Endian.little)).buffer.asUint8List(),
    );
    bytes.addAll(text);
  }
  for (final value in [150000001, 42]) {
    bytes.addAll(
      (ByteData(8)..setUint64(0, value, Endian.little)).buffer.asUint8List(),
    );
  }
  return bytes;
}

class _Transport {
  _Transport(this.sender, this.publicKey, {required bool conflict}) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final path = options.path;
          Object payload;
          if (options.method == 'GET' &&
              path == ApiConstants.walletAccountNonce(sender)) {
            nonceReads++;
            payload = {
              'data': {'nonce': '42'},
            };
          } else if (options.method == 'POST' &&
              path == ApiConstants.walletSend) {
            sends.add(options);
            if (conflict) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'error': {'code': 'CONFLICT'},
                    },
                  ),
                ),
              );
              return;
            }
            payload = {
              'status': 'submitted',
              'hash': _submissionHash,
              'settled': false,
            };
          } else if (options.method == 'GET' &&
              path == ApiConstants.publicBalance(sender.substring(2))) {
            payload = {
              'address': sender,
              'balance': '1000000000', // 10 WRF in integer base units.
              'height': 10262,
              'earned': '0',
            };
          } else if (options.method == 'GET' &&
              path.startsWith('/wallet/$sender/transactions?')) {
            payload = {'data': [], 'complete': true};
          } else {
            handler.reject(
              DioException(
                requestOptions: options,
                error: 'Unexpected smoke route',
              ),
            );
            return;
          }
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: payload),
          );
        },
      ),
    );
  }

  final String sender;
  final List<int> publicKey;
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1/api'));
  final List<RequestOptions> sends = [];
  int nonceReads = 0;
}
