import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/dio_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../services/api/api_client.dart';
import '../models/achievement_model.dart';
import '../models/leaderboard_entry_model.dart';
import '../models/reward_model.dart';

final gamificationRepositoryProvider = Provider<GamificationRepository>((ref) {
  return GamificationRepository(ref.watch(apiClientProvider).dio);
});

class GamificationRepository {
  final Dio _dio;

  GamificationRepository(this._dio);

  Future<Either<Failure, List<AchievementModel>>> getAchievements(
    String userId,
  ) async {
    try {
      final response = await _dio.get(ApiConstants.achievements(userId));
      final list = _extractList(response.data);
      final achievements = list
          .whereType<Map>()
          .map((e) => _mapAchievement(Map<String, dynamic>.from(e)))
          .toList();
      return Right(achievements);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Claims the reward for an earned achievement.
  ///
  /// POSTs to [ApiConstants.claimReward] with `userId` and `achievementId` in
  /// the request body. Returns a [RewardResult] on success.
  Future<Either<Failure, RewardResult>> claimReward(
    String userId,
    String achievementId,
  ) async {
    try {
      final response = await _dio.post(
        ApiConstants.claimReward(achievementId),
        data: <String, dynamic>{
          'userId': userId,
          'achievementId': achievementId,
        },
      );
      final payload = response.data;
      Map<String, dynamic> map;
      if (payload is Map) {
        map = Map<String, dynamic>.from(payload);
        // Backend ece94c9d rewards.ts:694-700: only the exact minimal body
        // acknowledges without payout data. The full response at :766-793
        // shares these flags (reward-payout-settlement.ts:130-140) but retains
        // reward data and a settlement transaction hash.
        final settlement = map['settlement'];
        final alreadyClaimed = map['alreadyClaimed'] == true;
        if (map.length == 3 &&
            map['success'] == true &&
            map['alreadyClaimed'] == true &&
            settlement is Map &&
            settlement.length == 2 &&
            settlement['state'] == 'settled' &&
            settlement['terminal'] == true) {
          return const Right(RewardResult.alreadyClaimed());
        }
        // Unwrap common envelope patterns.
        if (map.containsKey('data') && map['data'] is Map) {
          map = Map<String, dynamic>.from(map['data'] as Map);
        } else if (map.containsKey('reward') && map['reward'] is Map) {
          map = Map<String, dynamic>.from(map['reward'] as Map);
        }
        map = <String, dynamic>{
          ...map,
          'alreadyClaimed': alreadyClaimed || map['alreadyClaimed'] == true,
          'txHash':
              map['txHash'] ??
              (settlement is Map ? settlement['txHash'] : null),
        };
      } else {
        map = <String, dynamic>{};
      }
      return Right(RewardResult.fromJson(map));
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Fetches the reward claim history for [userId].
  Future<Either<Failure, List<RewardHistoryEntry>>> getRewardHistory(
    String userId,
  ) async {
    try {
      final response = await _dio.get(
        ApiConstants.rewardHistory,
        queryParameters: <String, dynamic>{'userId': userId},
      );
      final list = _extractList(response.data);
      final entries = list
          .whereType<Map>()
          .map((e) => RewardHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return Right(entries);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Detail tag carried by the [NotAvailableFailure] for an unprovable board.
  static const String earningsUnavailableDetail = 'earnings';

  static const NotAvailableFailure _earningsUnavailable = NotAvailableFailure(
    'Earnings unavailable right now',
    detail: earningsUnavailableDetail,
    statusCode: 503,
  );

  static bool _flagsUnavailable(dynamic data) {
    if (data is! Map) return false;
    final u = data['unavailable'];
    return u is List && u.isNotEmpty;
  }

  // The formatter uses eight decimal places; never label unknown units WRF.
  static bool _hasEarningsUnits(dynamic data) {
    if (data is! Map ||
        data['success'] != true ||
        data['earningsScope'] != 'lifetime') {
      return false;
    }
    final units = data['amountUnits'];
    if (units is! Map) return false;
    final fields = units['fields'];
    return units['denomination'] == 'WRF' &&
        units['baseUnitDecimals'] == 8 &&
        units['baseUnitsPerUnit'] == '100000000' &&
        units['available'] == true &&
        fields is Map &&
        fields['entries[].earningsBaseUnits'] == 'base_units' &&
        fields['entries[].earningsWrf'] == 'display_units';
  }

  /// Chain-earnings board. All-or-nothing: a 503, an `unavailable` marker, or
  /// any row whose amount cannot be parsed yields a failure, never a partial
  /// or empty list. Only a clean 200 with `entries: []` is an empty board.
  Future<Either<Failure, List<LeaderboardEntry>>> getLeaderboard() async {
    try {
      final response = await _dio.get(
        ApiConstants.leaderboard,
        // Insertion order is part of the public edge allowlist contract.
        queryParameters: <String, dynamic>{
          'metric': 'earnings',
          'period': '7d',
          'limit': 30,
        },
      );
      if (_flagsUnavailable(response.data)) {
        return const Left(_earningsUnavailable);
      }
      // Only a Map with a List `entries` is a board. Anything else (empty
      // object, string, bare list, null/object entries) is unavailable, never
      // an empty list.
      final data = response.data;
      final list = data is Map ? data['entries'] : null;
      if (list is! List || !_hasEarningsUnits(data)) {
        return const Left(_earningsUnavailable);
      }
      final entries = <LeaderboardEntry>[];
      for (final item in list) {
        if (item is! Map) return const Left(_earningsUnavailable);
        entries.add(
          LeaderboardEntry.fromEarningsJson(Map<String, dynamic>.from(item)),
        );
      }
      return Right(entries);
    } on DioException catch (e) {
      if (_flagsUnavailable(e.response?.data)) {
        return const Left(_earningsUnavailable);
      }
      return Left(DioErrorMapper.map(e));
    } on FormatException {
      return const Left(_earningsUnavailable);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  List<dynamic> _extractList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is! Map) return const <dynamic>[];

    final map = Map<String, dynamic>.from(payload);
    for (final key in const ['items', 'achievements', 'leaderboard', 'data']) {
      final candidate = map[key];
      if (candidate is List) return candidate;
      if (candidate is Map) {
        final nested = _extractList(candidate);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const <dynamic>[];
  }

  AchievementModel _mapAchievement(Map<String, dynamic> json) {
    final achievementData = json['achievement'] is Map
        ? <String, dynamic>{
            ...json,
            ...Map<String, dynamic>.from(json['achievement'] as Map),
          }
        : json;
    final achievementId =
        achievementData['achievementId']?.toString() ??
        achievementData['id']?.toString() ??
        'achievement';
    final normalizedProgress = _normalizeProgress(
      achievementData['progress'] ??
          achievementData['progressPercent'] ??
          achievementData['progressPercentage'],
    );
    final metadata = achievementData['metadata'];

    return AchievementModel(
      id: achievementData['id']?.toString() ?? achievementId,
      name:
          achievementData['name']?.toString() ??
          achievementData['title']?.toString() ??
          _titleize(achievementId),
      description:
          achievementData['description']?.toString() ??
          _metadataDescription(metadata) ??
          'Track progress for ${_titleize(achievementId)}',
      tier:
          achievementData['tier']?.toString() ??
          achievementData['difficulty']?.toString() ??
          'bronze',
      progress: normalizedProgress,
      earned:
          achievementData['earned'] == true ||
          achievementData['completed'] == true ||
          achievementData['claimedReward'] == true ||
          normalizedProgress >= 1,
      earnedAt:
          achievementData['earnedAt']?.toString() ??
          achievementData['completedAt']?.toString() ??
          achievementData['claimedAt']?.toString(),
    );
  }

  double _normalizeProgress(dynamic value) {
    if (value is num) {
      if (value > 1) return (value / 100).clamp(0, 1).toDouble();
      return value.clamp(0, 1).toDouble();
    }

    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return 0;
    final parsed = double.tryParse(raw.replaceAll('%', ''));
    if (parsed == null) return 0;
    if (parsed > 1) return (parsed / 100).clamp(0, 1);
    return parsed.clamp(0, 1);
  }

  String _titleize(String value) {
    return value
        .split(RegExp(r'[_\-\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String? _metadataDescription(dynamic metadata) {
    if (metadata is! Map) return null;
    final entries = Map<String, dynamic>.from(metadata).entries;
    if (entries.isEmpty) return null;
    final first = entries.first;
    return '${_titleize(first.key)}: ${first.value}';
  }
}
