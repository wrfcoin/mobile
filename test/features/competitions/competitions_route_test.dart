import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/competitions/data/repositories/competition_repository.dart';
import 'package:wrfcoin_mobile/features/competitions/presentation/screens/competitions_screen.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/stub_http_adapter.dart';
import 'competition_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('the Profile tab opens the weekly competition, signed out', (
    tester,
  ) async {
    final adapter = StubHttpAdapter(
      (o) => o.path == CompetitionRepository.listPath
          ? (200, emptyWeeks)
          : (200, emptyCurrent),
    );
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
        extraOverrides: [
          competitionRepositoryProvider.overrideWithValue(
            CompetitionRepository(stubDio(adapter)),
          ),
        ],
      ),
    );
    await pumpFrames(tester);
    final router = ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>).first),
    ).read(appRouterProvider);
    router.go('/profile');

    final entry = find.byTooltip('Weekly competition');
    await pumpUntilFound(tester, entry);
    await tester.tap(entry);
    await pumpUntilFound(tester, find.byType(CompetitionsScreen));

    await pumpUntilFound(tester, find.text('No points yet this week'));
    expect(
      adapter.requests.map((r) => r.path),
      containsAll([
        CompetitionRepository.listPath,
        CompetitionRepository.currentPath,
      ]),
    );
  });
}
