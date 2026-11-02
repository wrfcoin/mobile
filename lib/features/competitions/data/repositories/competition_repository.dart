import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/public_read.dart';
import '../../../../services/api/api_client.dart';
import '../models/competition_model.dart';

final competitionRepositoryProvider = Provider<CompetitionRepository>(
  (ref) => CompetitionRepository(ref.watch(apiClientProvider).dio),
);

/// The website's weekly competition routes (backend competition-routes.ts,
/// mounted at /api/competitions). Read-only and public; the shared client
/// attaches a wallet session when there is one, which only marks your own row.
class CompetitionRepository {
  CompetitionRepository(this._dio);

  final Dio _dio;

  static const listPath = '/competitions';
  static const currentPath = '/competitions/current';
  static final _week = RegExp(r'^\d{4}-W\d{2}$');

  Future<PublicRead<CompetitionList>> getWeeks() =>
      readPublicJson(_dio, listPath, CompetitionList.fromJson);

  /// [week] null is this week.
  Future<PublicRead<CompetitionStandings>> getStandings(String? week) {
    if (week != null && !_week.hasMatch(week)) {
      return Future.value(const PublicNotFound());
    }
    return readPublicJson(
      _dio,
      week == null ? currentPath : '/competitions/$week',
      CompetitionStandings.fromJson,
    );
  }
}
