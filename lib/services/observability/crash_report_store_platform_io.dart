import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'crash_report_store.dart';
import 'file_crash_reporter.dart';

Future<CrashReportStore?> createLocalCrashReportStore() async {
  final support = await getApplicationSupportDirectory();
  return FileCrashReporter(
    Directory('${support.path}/crash-reports'),
    platform: Platform.operatingSystem,
    // Honest when the build did not provide a version; never invent one.
    appVersion: const String.fromEnvironment(
      'FLUTTER_BUILD_NAME',
      defaultValue: 'unavailable',
    ),
  );
}
