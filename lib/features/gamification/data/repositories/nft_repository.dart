import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/dio_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../services/api/api_client.dart';
import '../models/weather_nft_model.dart';

final nftRepositoryProvider = Provider<NftRepository>((ref) {
  return NftRepository(ref.watch(apiClientProvider).dio);
});

class NftRepository {
  const NftRepository(this._dio);

  final Dio _dio;

  /// Fetches the NFT portfolio for [userId].
  ///
  /// Returns an empty list on 404 (backend not yet deployed for this user).
  /// TODO(#34): remove the empty-list 404 shortcut when backend is live.
  Future<Either<Failure, List<WeatherNftModel>>> getPortfolio(
    String userId,
  ) async {
    try {
      final response = await _dio.get(ApiConstants.nftPortfolio(userId));
      final nfts = _parseList(response.data)
          .whereType<Map>()
          .map((e) => WeatherNftModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return Right(nfts);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const Right([]);
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Claims an NFT for [userId] by [nftId].
  ///
  /// TODO(#34): remove stub when backend POST /nft/claim is live.
  Future<Either<Failure, WeatherNftModel>> claimNft(
    String userId,
    String nftId,
  ) async {
    try {
      final response = await _dio.post(
        ApiConstants.nftClaim,
        data: <String, dynamic>{'userId': userId, 'nftId': nftId},
      );
      final payload = response.data;
      final map = payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{};
      final data = map['nft'] is Map
          ? Map<String, dynamic>.from(map['nft'] as Map)
          : map;
      return Right(WeatherNftModel.fromJson(data));
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  List<dynamic> _parseList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is Map) {
      final m = Map<String, dynamic>.from(payload);
      for (final key in const ['nfts', 'items', 'data']) {
        if (m[key] is List) return m[key] as List;
      }
    }
    return const [];
  }
}
