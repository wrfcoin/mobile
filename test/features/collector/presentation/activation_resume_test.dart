import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';

import '../../../test_helpers/app_harness.dart';
import '../../../test_helpers/fakes.dart';

class _Worker extends FakeSyncWorker {
  int resumes = 0;
  Completer<SyncRunResult>? pending;
  @override
  Future<SyncRunResult> syncOnResume({bool includeIdempotencyKey = false}) {
    resumes++;
    return (pending = Completer<SyncRunResult>()).future;
  }

  void finish() => pending!.complete(
    const SyncRunResult(
      acceptedCount: 0,
      failedCount: 0,
      pendingCount: 0,
      reason: SyncRunReason.idle,
    ),
  );
}

void main() {
  testWidgets(
    'mounted app resumes once, holds concurrent triggers, and disposes its observer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = createTestDatabase();
      final worker = _Worker();
      final harness = await buildTestApp(db: db) as ProviderScope;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...harness.overrides.where((o) => o.origin != syncWorkerProvider),
            syncWorkerProvider.overrideWithValue(worker),
          ],
          child: harness.child,
        ),
      );
      await pumpFrames(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(worker.resumes, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);
      expect(worker.resumes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);
      expect(worker.resumes, 1, reason: 'one in-flight run, no retry spam');
      worker.finish();
      await pumpFrames(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);
      expect(worker.resumes, 1);
      await db.close();
    },
  );
}
