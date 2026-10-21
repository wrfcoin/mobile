import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'bootstrap/app_overrides.dart';
import 'core/constants/api_constants.dart';
import 'services/observability/crash_reporter.dart';
import 'services/background/sensor_worker.dart';
import 'services/referral/referral_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  // Fail before constructing a network client when a release lacks a usable
  // explicitly selected API endpoint (#264). DNS is checked at build preflight.
  final releaseUrlProblem = ApiConstants.releaseUrlProblem(
    ApiConstants.baseUrl,
  );
  if (kReleaseMode && releaseUrlProblem != null) {
    throw StateError(
      'FATAL: release build has no usable API_BASE_URL: $releaseUrlProblem',
    );
  }

  await initializeBackgroundWork();

  // Server-initiated push is out of testnet scope (mobile#271, Option A):
  // alerts are delivered while the app is open, so no remote push registration starts.

  final container = await createAppContainer();
  final referralService = container.read(referralServiceProvider);
  final initialRouteName =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  if (initialRouteName.isNotEmpty && initialRouteName != '/') {
    final initialUri = Uri.tryParse(initialRouteName);
    if (initialUri != null) {
      await referralService.captureInviteUri(initialUri);
    }
  }

  final crashReporter = container.read(crashReporterProvider);
  configureGlobalErrorHandling(crashReporter);

  runZonedGuarded(
    () {
      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const WrfcoinApp(),
        ),
      );
    },
    (error, stackTrace) {
      unawaited(
        crashReporter.recordError(
          error,
          stackTrace,
          reason: 'run_zoned_guarded',
          fatal: true,
        ),
      );
    },
  );
}
