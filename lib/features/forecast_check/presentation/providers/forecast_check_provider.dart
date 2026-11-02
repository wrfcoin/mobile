import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/public_read.dart';
import '../../data/models/forecast_check_model.dart';
import '../../data/repositories/forecast_check_repository.dart';

final forecastCheckProvider =
    FutureProvider.autoDispose<PublicRead<ForecastCheckSummary>>(
      (ref) => ref.watch(forecastCheckRepositoryProvider).getSummary(),
    );
