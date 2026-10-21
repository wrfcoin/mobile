import 'dart:async';

/// Global test bootstrap (flutter_test loads this for every test file).
///
/// The sqlite3 2.x-era Linux loader override that lived here (#209) is gone:
/// sqlite3 3.x removed `package:sqlite3/open.dart` and loads its own compiled
/// SQLite through Dart build hooks, so the versioned-soname fallback is no
/// longer needed — or possible.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
