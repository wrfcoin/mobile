import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../models/faucet_models.dart';

/// Thin HTTP client over the backend faucet onboarding endpoints.
///
/// Backend contract — `backend/server/routes/onboarding-routes.ts`:
///   * `POST /onboarding/faucet/challenge` → `200 { challengeId, question }`
///   * `POST /onboarding/faucet/claim`     → `200 { txHash, amount, balance }`
///     or `400/429/503 { error: { code, message } }`
class FaucetRemoteDataSource {
  final Dio _dio;

  FaucetRemoteDataSource(this._dio);

  /// Requests a fresh math-captcha challenge.
  Future<FaucetChallenge> requestChallenge() async {
    final response = await _dio.post(ApiConstants.faucetChallenge);
    return FaucetChallenge.fromJson(_unwrapMap(response.data));
  }

  /// Submits a solved challenge for [walletAddress] and dispenses tokens.
  ///
  /// Backend body: `{ walletAddress, challengeId, answer }`.
  Future<FaucetClaimResult> claim({
    required String walletAddress,
    required String challengeId,
    required int answer,
  }) async {
    final response = await _dio.post(
      ApiConstants.faucetClaim,
      // A timeout/5xx may occur after payment. Never replay this POST,
      // including through the shared client's auth-refresh interceptor.
      options: Options(extra: {'noRetry': true, 'noAuthRetry': true}),
      data: {
        'walletAddress': walletAddress,
        'challengeId': challengeId,
        'answer': answer,
      },
    );
    return FaucetClaimResult.fromJson(_unwrapMap(response.data));
  }

  /// Unwraps an optional `{ data: {...} }` envelope into a flat map.
  Map<String, dynamic> _unwrapMap(dynamic payload) {
    dynamic current = payload;

    while (current is Map) {
      final map = Map<String, dynamic>.from(current);
      final nested = map['data'];
      if (nested is Map) {
        current = nested;
        continue;
      }
      return map;
    }

    throw StateError('Expected faucet API response to be an object.');
  }
}
