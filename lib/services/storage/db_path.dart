import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Each background connection has its own bounded SQLite writer admission.
QueryExecutor openNativeAppDatabase(
  File file,
) => NativeDatabase.createInBackground(
  file,
  setup: (db) {
    // Collector and foreground connections can contend for the writer.
    // SQLite waits in the background isolate; the operation is not replayed.
    // Use actual monotonic time: native Unix sleeps can be interrupted, so
    // SQLite's requested-sleep accounting can expire ahead of wall time.
    final waited = Stopwatch();
    db.busyHandler = (count) {
      if (count == 0) waited.reset();
      waited.start();
      const budget = Duration(seconds: 5);
      final remaining = budget - waited.elapsed;
      if (remaining <= Duration.zero) return false;
      final pause = remaining < const Duration(milliseconds: 10)
          ? remaining
          : const Duration(milliseconds: 10);
      sleep(pause);
      return waited.elapsed < budget;
    };
  },
);

LazyDatabase openAppDatabase() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'wrfcoin.sqlite'));
    return openNativeAppDatabase(file);
  });
}
