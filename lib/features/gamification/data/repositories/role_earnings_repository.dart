import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
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
    // The role board has no index for weather contributions and answers
    // `unavailable`. Station rewards are on the weather board, as on the web.
    if (role == EarningsRole.contribution) {
      final response = await dio.get(
        ApiConstants.leaderboard,
        // Insertion order is part of the public edge allowlist contract.
        queryParameters: <String, dynamic>{
          'metric': 'earnings',
          'period': period.wire,
          'limit': 30,
        },
      );
      return RoleLeaderboard.parseWeather(response.data, period);
    }
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

  /// The signed-in viewer's own figures, or null when no public board shows
  /// them.
  ///
  /// The edge admits profiles only by opaque key and has no address lookup, by
  /// design, and the key can't be derived on the phone. A board row the server
  /// marks `isYou` is the only source of it, so a viewer on no top-30 board has
  /// no card. A read that fails while nothing was found throws, so that stays
  /// distinct from "not on a board".
  Future<OwnRoleEarnings?> ownEarnings() async {
    Future<RoleEarningsRow?> ownRow(EarningsRole role) async {
      final board = await leaderboard(role, EarningsPeriod.all);
      return board.rows.where((row) => row.isYou).firstOrNull;
    }

    RoleEarningsRow? weatherRow;
    var weatherBoardRead = false;
    Object? readFailure;
    try {
      weatherRow = await ownRow(EarningsRole.contribution);
      weatherBoardRead = true;
    } catch (e) {
      readFailure = e;
    }

    var key = weatherRow?.profileKey ?? '';
    for (final role in const [EarningsRole.producer, EarningsRole.attester]) {
      if (key.isNotEmpty) break;
      try {
        key = (await ownRow(role))?.profileKey ?? '';
      } catch (e) {
        readFailure = e;
      }
    }

    OwnRoleEarnings? profile;
    if (key.isNotEmpty) {
      try {
        final response = await dio.get(
          '/operators/${Uri.encodeComponent(key)}/profile',
        );
        profile = OwnRoleEarnings.parse(response.data);
      } catch (e) {
        readFailure = e;
      }
    }
    if (weatherRow == null && profile == null) {
      // Only a key with no readable profile, or a failed board, is unknown.
      if (readFailure != null) {
        throw const FormatException('Own earnings unavailable');
      }
      return null;
    }
    return OwnRoleEarnings.combine(
      profile: profile,
      weatherRow: weatherRow,
      weatherBoardRead: weatherBoardRead,
    );
  }
}
