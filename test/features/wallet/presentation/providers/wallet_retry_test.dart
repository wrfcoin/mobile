// mobile#320: Riverpod retries a failed provider ~10 times over ~40 s. For
// the wallet that is right for a transient failure (a 5xx, a dropped
// connection, a timeout) and wrong for a definite answer: a 401 (no
// session), a 403 (the server refuses this session, seen on the owner's
// phone as 11x GET /api/wallet/<addr> -> 403), a 404 or "not available"
// never fixes itself, and the retries only hide the answer behind
// "Loading". Both directions are pinned here, so neither "retry everything"
// nor "retry nothing" survives.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:dio/dio.dart';

import '../../../../test_helpers/fakes.dart';

class _SignedInApiClient extends ApiClient {
  _SignedInApiClient() : super(dio: Dio());

  @override
  Future<bool> ensureWalletSession() async => true;
}

class _FailingRepository extends FakeWalletRepository {
  _FailingRepository(this.failure);

  final Failure failure;
  int walletRequests = 0;

  @override
  Future<Either<Failure, WalletModel>> getWallet(String address) async {
    walletRequests++;
    return Left(failure);
  }
}

Future<int> _requestsOver45s(WidgetTester tester, Failure failure) async {
  final storage = InMemoryKeyValueStorage();
  await storage.write(key: 'wrf_address', value: 'wrf1testwallet0000000000');
  final repo = _FailingRepository(failure);
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(_SignedInApiClient()),
      walletRepositoryProvider.overrideWithValue(repo),
      keyManagerProvider.overrideWithValue(
        KeyManager(
          biometric: BiometricService(client: FakeLocalAuthClient()),
          storage: storage,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(walletProvider, (_, _) {});
  addTearDown(sub.close);

  // Riverpod's timers run on the widget tester's fake clock.
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  return repo.walletRequests;
}

void main() {
  testWidgets('a 401 is asked once, not retried', (tester) async {
    expect(await _requestsOver45s(tester, const AuthFailure()), 1);
  });

  testWidgets('a 403 is asked once, not retried', (tester) async {
    expect(
      await _requestsOver45s(
        tester,
        const ServerFailure('Access denied', statusCode: 403),
      ),
      1,
    );
  });

  testWidgets('a 404 is asked once, not retried', (tester) async {
    expect(
      await _requestsOver45s(
        tester,
        const ServerFailure('Not found', statusCode: 404),
      ),
      1,
    );
  });

  testWidgets('a 5xx is still retried', (tester) async {
    expect(
      await _requestsOver45s(
        tester,
        const ServerFailure('Server error. Please try again later.'),
      ),
      greaterThan(1),
    );
  });

  testWidgets('a network failure is still retried', (tester) async {
    expect(
      await _requestsOver45s(tester, const NetworkFailure()),
      greaterThan(1),
    );
  });

  group('retryUnlessDefinite', () {
    Duration? retry(Failure f) => retryUnlessDefinite(0, f);

    test('definite answers are not retried', () {
      expect(retry(const AuthFailure()), isNull);
      expect(
        retry(const ServerFailure('Access denied', statusCode: 403)),
        isNull,
      );
      expect(retry(const ServerFailure('Not found', statusCode: 404)), isNull);
      expect(retry(const ServerFailure('Invalid', statusCode: 400)), isNull);
      expect(retry(const NotAvailableFailure('Not on testnet')), isNull);
      expect(
        retry(
          const NotAvailableFailure(
            'No Reader credential',
            detail: 'CORE4_READER_CREDENTIAL_UNCONFIGURED',
            statusCode: 503,
          ),
        ),
        isNull,
      );
    });

    test('transient failures keep the default retry', () {
      expect(retry(const ServerFailure('Server error.')), isNotNull);
      expect(
        retry(const ServerFailure('Bad gateway', statusCode: 502)),
        isNotNull,
      );
      expect(retry(const NetworkFailure()), isNotNull);
      expect(retry(const ServerFailure('Timeout', statusCode: 408)), isNotNull);
      expect(
        retry(const ServerFailure('Slow down', statusCode: 429)),
        isNotNull,
      );
      expect(
        retryUnlessDefinite(0, const ServerFailure('Server error.')),
        ProviderContainer.defaultRetry(0, const ServerFailure('Server error.')),
      );
    });
  });
}
