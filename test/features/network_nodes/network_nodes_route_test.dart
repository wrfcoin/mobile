import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/explorer/presentation/screens/chain_screen.dart';
import 'package:wrfcoin_mobile/features/network_nodes/data/repositories/network_nodes_repository.dart';
import 'package:wrfcoin_mobile/features/network_nodes/presentation/screens/network_nodes_screen.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/stub_http_adapter.dart';
import 'network_nodes_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('the Chain screen opens Nodes, signed out', (tester) async {
    final adapter = StubHttpAdapter((_) => (200, loadedNodes));
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
        extraOverrides: [
          networkNodesRepositoryProvider.overrideWithValue(
            NetworkNodesRepository(stubDio(adapter)),
          ),
        ],
      ),
    );
    await pumpFrames(tester);
    final router = ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>).first),
    ).read(appRouterProvider);
    router.go('/wallet/chain');
    await pumpUntilFound(tester, find.byType(ChainScreen));

    final entry = find.byTooltip('Producers and bonded nodes');
    await pumpUntilFound(tester, entry);
    await tester.tap(entry);
    await pumpUntilFound(tester, find.byType(NetworkNodesScreen));

    await pumpUntilFound(tester, find.text('Attesters'));
    expect(adapter.requests.single.path, NetworkNodesRepository.path);
  });
}
