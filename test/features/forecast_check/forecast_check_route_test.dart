import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/forecast_check/data/repositories/forecast_check_repository.dart';
import 'package:wrfcoin_mobile/features/forecast_check/presentation/screens/forecast_check_screen.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/stub_http_adapter.dart';
import 'forecast_check_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('the Weather tab opens Forecast check, signed out', (
    tester,
  ) async {
    final adapter = StubHttpAdapter((_) => (200, emptySummary));
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
        extraOverrides: [
          forecastCheckRepositoryProvider.overrideWithValue(
            ForecastCheckRepository(stubDio(adapter)),
          ),
        ],
      ),
    );
    await pumpFrames(tester);
    final router = ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>).first),
    ).read(appRouterProvider);
    router.go('/weather');

    final entry = find.byTooltip('Forecast check');
    await pumpUntilFound(tester, entry);
    await tester.tap(entry);
    await pumpUntilFound(tester, find.byType(ForecastCheckScreen));

    await pumpUntilFound(tester, find.text('Hand in your forecast'));
    expect(adapter.requests.single.path, ForecastCheckRepository.summaryPath);
  });
}
