import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'crash_reporter.dart';
import 'crash_report_store_platform_stub.dart'
    if (dart.library.io) 'crash_report_store_platform_io.dart'
    as platform;

abstract class CrashReportStore implements CrashReporter {
  Future<int> count();
  Future<List<XFile>> exportFiles();
  Future<void> clear();
}

final localCrashReportStoreProvider = FutureProvider<CrashReportStore?>((ref) {
  return platform.createLocalCrashReportStore();
});

final localCrashReportCountProvider = FutureProvider.autoDispose<int?>((
  ref,
) async {
  final store = await ref.watch(localCrashReportStoreProvider.future);
  return store?.count();
});
