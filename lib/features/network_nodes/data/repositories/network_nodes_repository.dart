import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/public_read.dart';
import '../../../../services/api/api_client.dart';
import '../models/network_nodes_model.dart';

final networkNodesRepositoryProvider = Provider<NetworkNodesRepository>(
  (ref) => NetworkNodesRepository(ref.watch(apiClientProvider).dio),
);

/// The website's public producer and bonded-node read (backend
/// network-nodes-routes.ts, mounted at /api/network). No wallet or login.
class NetworkNodesRepository {
  NetworkNodesRepository(this._dio);

  final Dio _dio;

  static const path = '/network/nodes';

  Future<PublicRead<NetworkNodes>> getNodes() =>
      readPublicJson(_dio, path, NetworkNodes.fromJson);
}
