import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../models/carbon_lottery_models.dart';

class CarbonLotteryRemoteDataSource {
  final Dio _dio;

  CarbonLotteryRemoteDataSource(this._dio);

  Future<CarbonLotterySnapshot> getDashboard(String walletAddress) async {
    final response = await _dio.get(
      ApiConstants.carbonLotteryDashboard(walletAddress),
    );
    return CarbonLotterySnapshot.fromJson(_unwrapMap(response.data));
  }

  Future<CarbonLotteryActionRequest> requestDeposit({
    required String walletAddress,
    required String amountCredits,
  }) {
    return _requestAction(
      endpoint: ApiConstants.carbonLotteryDeposit,
      action: CarbonLotteryAction.deposit,
      walletAddress: walletAddress,
      amountCredits: amountCredits,
    );
  }

  Future<CarbonLotteryActionRequest> requestWithdraw({
    required String walletAddress,
    required String amountCredits,
  }) {
    return _requestAction(
      endpoint: ApiConstants.carbonLotteryWithdraw,
      action: CarbonLotteryAction.withdraw,
      walletAddress: walletAddress,
      amountCredits: amountCredits,
    );
  }

  Future<CarbonLotteryActionRequest> _requestAction({
    required String endpoint,
    required CarbonLotteryAction action,
    required String walletAddress,
    required String amountCredits,
  }) async {
    final response = await _dio.post(
      endpoint,
      data: {
        'walletAddress': walletAddress,
        'amountCredits': amountCredits,
        'action': action.name,
        'requestType': 'signed_transaction_request',
      },
    );

    return CarbonLotteryActionRequest.fromJson(
      _unwrapMap(response.data),
      action: action,
      walletAddress: walletAddress,
      amountCredits: amountCredits,
    );
  }

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

    throw StateError('Expected carbon lottery API response to be an object.');
  }
}
