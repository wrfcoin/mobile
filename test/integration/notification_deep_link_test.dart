import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/services/notifications/notification_payload_router.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';

// ── Spy helpers ───────────────────────────────────────────────────────────────

class _SpyNavigator implements AppNavigator {
  final List<String> navigations = <String>[];

  @override
  void go(String location, {Object? extra}) => navigations.add(location);
}

class _MemoryLogSink implements LogSink {
  final List<AppLogEntry> entries = <AppLogEntry>[];

  @override
  void write(AppLogEntry entry) => entries.add(entry);
}

NotificationPayloadRouter _makeRouter(
  _SpyNavigator nav,
  _MemoryLogSink sink,
) {
  return NotificationPayloadRouter(
    router: nav,
    logger: AppLogger(sinks: [sink], verbose: true),
  );
}

String _json(Map<String, dynamic> data) => jsonEncode(data);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(
      const <String, Object>{'onboarding.completed': true},
    );
  });

  group('notification deep-link integration', () {
    late _SpyNavigator nav;
    late _MemoryLogSink logSink;
    late NotificationPayloadRouter subject;

    setUp(() {
      nav = _SpyNavigator();
      logSink = _MemoryLogSink();
      subject = _makeRouter(nav, logSink);
    });

    // ── Scenario 1: alert tap opens /weather/alerts ────────────────────────

    testWidgets('alert notification tap opens /weather/alerts', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => subject.handlePayload(
                  _json(<String, dynamic>{'type': 'alert', 'alertId': 'a-1'}),
                ),
                child: const Text('Tap'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(nav.navigations, contains('/weather/alerts'));
      expect(
        logSink.entries.map((e) => e.event),
        containsAll(['notification.open', 'notification.route_success']),
      );
    });

    // ── Scenario 2: malformed payload → /weather (safe default) ───────────

    testWidgets(
        'malformed payload navigates to /weather and emits fallback warning',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    subject.handlePayload('{"type": BROKEN JSON!!}'),
                child: const Text('Tap'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(nav.navigations, contains('/weather'));
      expect(nav.navigations, isNot(contains('/weather/alerts')));

      final fallback = logSink.entries
          .where((e) => e.event == 'notification.route_fallback')
          .toList();
      expect(fallback, isNotEmpty);
      expect(fallback.first.level, AppLogLevel.warning);
      expect(
        logSink.entries.map((e) => e.event),
        isNot(contains('notification.route_success')),
      );
    });

    // ── Scenario 3: each known type routes correctly ───────────────────────

    testWidgets('proposal routes to /govern', (tester) async {
      await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: Container())));

      final outcome = await subject.handlePayload(
        _json(<String, dynamic>{'type': 'proposal', 'proposalId': 'p-42'}),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(outcome, RouteOutcome.success);
      expect(nav.navigations.any((r) => r.startsWith('/govern')), isTrue);
    });

    testWidgets('wallet_tx routes to /wallet', (tester) async {
      await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: Container())));

      final outcome = await subject.handlePayload(
        _json(<String, dynamic>{'type': 'wallet_tx', 'txId': '0xfeed'}),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(outcome, RouteOutcome.success);
      expect(nav.navigations, contains('/wallet'));
    });

    testWidgets('collector_sync routes to /collect', (tester) async {
      await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: Container())));

      final outcome = await subject.handlePayload(
        _json(<String, dynamic>{'type': 'collector_sync'}),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(outcome, RouteOutcome.success);
      expect(nav.navigations, contains('/collect'));
    });

    testWidgets('unknown type is a fallback to /weather', (tester) async {
      await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: Container())));

      final outcome = await subject.handlePayload(
        _json(<String, dynamic>{'type': 'nope'}),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(outcome, RouteOutcome.fallback);
      expect(nav.navigations, contains('/weather'));
    });
  });
}
