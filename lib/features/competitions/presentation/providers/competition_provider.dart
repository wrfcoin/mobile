import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/public_read.dart';
import '../../data/models/competition_model.dart';
import '../../data/repositories/competition_repository.dart';

final competitionWeeksProvider =
    FutureProvider.autoDispose<PublicRead<CompetitionList>>(
      (ref) => ref.watch(competitionRepositoryProvider).getWeeks(),
    );

/// Standings of one ISO week; null is this week.
final competitionStandingsProvider = FutureProvider.autoDispose
    .family<PublicRead<CompetitionStandings>, String?>(
      (ref, week) =>
          ref.watch(competitionRepositoryProvider).getStandings(week),
    );
