import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api/api_client.dart';
import 'explorer_models.dart';

final explorerRemoteDataSourceProvider = Provider<ExplorerRemoteDataSource>(
  (ref) => ExplorerRemoteDataSource(ref.watch(apiClientProvider).dio),
);

/// Public reads only (backend B1): no wallet, no auth, no addresses.
class ExplorerRemoteDataSource {
  ExplorerRemoteDataSource(this._dio);

  final Dio _dio;

  /// Never throws: a failed or malformed answer is the degraded summary.
  Future<ExplorerSummary> fetchSummary({CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/explorer/summary',
        cancelToken: cancelToken,
      );
      final data = response.data;
      if (data is Map) {
        return ExplorerSummary.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {
      // fall through
    }
    return const ExplorerSummary.degraded();
  }

  /// Newest first; null when the request failed.
  Future<List<ChainBlock>?> fetchRecentBlocks({
    int limit = 15,
    CancelToken? cancelToken,
  }) async {
    // Public mobile reads share the backend's anonymous 30-block window.
    final boundedLimit = limit.clamp(1, 30);
    try {
      final response = await _dio.get<dynamic>(
        '/blockchain/blocks',
        queryParameters: {'limit': boundedLimit},
        cancelToken: cancelToken,
      );
      final data = response.data;
      final list = data is Map ? (data['blocks'] ?? data['data']) : null;
      if (list is! List) return null;
      final blocks =
          list
              .whereType<Map>()
              .map((b) => ChainBlock.fromJson(Map<String, dynamic>.from(b)))
              .where((b) => b.height != null)
              .toList()
            ..sort((a, b) => b.height!.compareTo(a.height!));
      return blocks.take(boundedLimit).toList();
    } catch (_) {
      return null;
    }
  }

  Future<ChainBlock?> fetchBlock(int height, {CancelToken? cancelToken}) async {
    if (height < 0) return null;
    try {
      final response = await _dio.get<dynamic>(
        '/blockchain/blocks/$height',
        cancelToken: cancelToken,
      );
      final data = response.data;
      if (data is Map) {
        return ChainBlock.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {
      // fall through
    }
    return null;
  }
}
