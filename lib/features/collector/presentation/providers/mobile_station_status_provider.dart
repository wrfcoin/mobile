import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/storage/local_db.dart';
import '../../data/repositories/collector_repository_impl.dart';
import '../../data/services/mobile_station_status_service.dart';

final mobileStationStatusProvider = FutureProvider.autoDispose
    .family<MobileStationStatus, String>((ref, owner) {
      final repository = ref.watch(collectorRepositoryProvider);
      final store = repository.db;
      return MobileStationStatusService(
        apiClient: repository.apiClient,
        db: store is AppDatabase ? store : null,
      ).fetch(owner);
    });
