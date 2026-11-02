import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/public_read.dart';
import '../../data/models/network_nodes_model.dart';
import '../../data/repositories/network_nodes_repository.dart';

final networkNodesProvider =
    FutureProvider.autoDispose<PublicRead<NetworkNodes>>(
      (ref) => ref.watch(networkNodesRepositoryProvider).getNodes(),
    );
