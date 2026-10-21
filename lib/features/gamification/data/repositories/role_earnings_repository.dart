import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/api_client.dart';
import '../models/role_earnings_model.dart';

final roleEarningsRepositoryProvider = Provider<RoleEarningsRepository>(
  (ref) => RoleEarningsRepository(ref.watch(apiClientProvider).dio),
);

class RoleEarningsRepository {
  final Dio dio;
  RoleEarningsRepository(this.dio);
  Future<bool> enabled() async {
    try {
      final j = object((await dio.get('/capabilities')).data);
      final status = object(object(j['features'])['earningsRead'])['status'];
      if (status is! String) {
        throw const FormatException('Capability status unavailable');
      }
      return const ['operational', 'degraded', 'configured'].contains(status);
    } catch (_) {
      // UNKNOWN must stay distinct from an explicit disabled response.
      // Keep transport details out of the UI and do not retry automatically.
      throw const FormatException('Earnings capability unavailable');
    }
  }

  Future<RoleLeaderboard> leaderboard(
    EarningsRole role,
    EarningsPeriod period,
  ) async {
    final response = await dio.get(
      '/earnings/leaderboard',
      queryParameters: <String, dynamic>{
        'role': role.name,
        'period': period.wire,
        'limit': 30,
      },
    );
    return RoleLeaderboard.parse(response.data, role, period);
  }

  Future<OwnRoleEarnings> ownProfile(String address) async {
    final response = await dio.get(
      '/operators/${Uri.encodeComponent(address)}/profile',
    );
    return OwnRoleEarnings.parse(response.data);
  }
}
