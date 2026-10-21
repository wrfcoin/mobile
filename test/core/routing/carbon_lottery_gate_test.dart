import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/data/datasources/carbon_lottery_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/data/repositories/carbon_lottery_repository_impl.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/presentation/screens/carbon_lottery_dashboard_screen.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';

/// mobile#268: the Carbon Lottery has no backend, so it is dark-launched
/// behind `enableCarbonLottery` (default off). The flag-on cases are the
/// control: they prove the finders and the request recorder can see the
/// feature when it is reachable.
void main() {
  late AppDatabase db;
  late List<String> lotteryRequests;

  setUp(() {
    db = createTestDatabase();
    lotteryRequests = <String>[];
  });

  tearDown(() async {
    await db.close();
  });

  Dio recordingDio() {
    final dio = Dio(BaseOptions(baseUrl: 'http://lottery.invalid/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          lotteryRequests.add(options.path);
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 404),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );
    return dio;
  }

  Future<GoRouter> pumpApp(WidgetTester tester, {required bool flagOn}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (flagOn) 'ff_enableCarbonLottery': true,
    });
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
        // These tests are about the loaded wallet tab.
        signedIn: true,
        extraOverrides: [
          carbonLotteryRemoteDataSourceProvider.overrideWithValue(
            CarbonLotteryRemoteDataSource(recordingDio()),
          ),
        ],
      ),
    );
    await pumpFrames(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>).first),
    );
    return container.read(appRouterProvider);
  }

  String currentPath(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  final lotteryButton = find.text('Carbon Lottery', skipOffstage: false);
  final faucetButton = find.text('Get Testnet Tokens', skipOffstage: false);

  testWidgets('default build: wallet tab shows no Carbon Lottery entry', (
    tester,
  ) async {
    final router = await pumpApp(tester, flagOn: false);
    router.go('/wallet');
    await pumpUntilFound(tester, faucetButton);

    expect(lotteryButton, findsNothing);
    expect(lotteryRequests, isEmpty);
  });

  testWidgets('default build: /wallet/lottery deep link redirects to /wallet', (
    tester,
  ) async {
    final router = await pumpApp(tester, flagOn: false);
    router.go('/wallet/lottery');
    await pumpUntilFound(tester, faucetButton);

    expect(currentPath(router), '/wallet');
    expect(find.byType(CarbonLotteryDashboardScreen), findsNothing);
    expect(lotteryRequests, isEmpty, reason: 'no carbon-lottery request');
  });

  testWidgets('flag on (control): wallet tab shows the entry', (tester) async {
    final router = await pumpApp(tester, flagOn: true);
    router.go('/wallet');
    await pumpUntilFound(tester, faucetButton);

    expect(lotteryButton, findsOneWidget);
  });

  testWidgets('flag on (control): /wallet/lottery builds the dashboard', (
    tester,
  ) async {
    final router = await pumpApp(tester, flagOn: true);
    router.go('/wallet/lottery');
    await pumpUntilFound(tester, find.byType(CarbonLotteryDashboardScreen));

    expect(currentPath(router), '/wallet/lottery');
    await pumpFrames(tester);
    expect(
      lotteryRequests,
      isNotEmpty,
      reason: 'the recorder sees lottery requests when the feature is on',
    );
  });
}
