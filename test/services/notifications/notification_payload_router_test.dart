import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/notifications/notification_payload_router.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';

class _SpyNavigator implements AppNavigator {
  final List<String> navigatedTo = <String>[];

  @override
  void go(String location, {Object? extra}) {
    navigatedTo.add(location);
  }
}

class _SpyLogSink implements LogSink {
  final List<AppLogEntry> entries = <AppLogEntry>[];

  @override
  void write(AppLogEntry entry) {
    entries.add(entry);
  }
}

void main() {
  late _SpyNavigator navigator;
  late _SpyLogSink logSink;
  late NotificationPayloadRouter subject;

  setUp(() {
    navigator = _SpyNavigator();
    logSink = _SpyLogSink();
    subject = NotificationPayloadRouter(
      router: navigator,
      logger: AppLogger(sinks: [logSink], verbose: true),
    );
  });

  String json(Map<String, dynamic> payload) => jsonEncode(payload);

  group('proposal type', () {
    test('routes to /govern', () async {
      final outcome = await subject.handlePayload(
        json({'type': 'proposal', 'proposalId': 'prop-42'}),
      );

      expect(outcome, RouteOutcome.success);
      expect(navigator.navigatedTo, contains(startsWith('/govern')));
    });

    test('emits route_success telemetry', () async {
      await subject.handlePayload(json({'type': 'proposal', 'proposalId': 'p1'}));

      final events = logSink.entries.map((e) => e.event).toList();
      expect(events, contains('notification.open'));
      expect(events, contains('notification.route_success'));
    });
  });

  group('alert type', () {
    test('routes to /weather/alerts', () async {
      final outcome = await subject.handlePayload(
        json({'type': 'alert', 'alertId': 'a-1'}),
      );

      expect(outcome, RouteOutcome.success);
      expect(navigator.navigatedTo, contains('/weather/alerts'));
    });
  });

  group('wallet_tx type', () {
    test('routes to /wallet', () async {
      final outcome = await subject.handlePayload(
        json({'type': 'wallet_tx', 'txId': '0xabc'}),
      );

      expect(outcome, RouteOutcome.success);
      expect(navigator.navigatedTo, contains('/wallet'));
    });
  });

  group('collector_sync type', () {
    test('routes to /collect', () async {
      final outcome = await subject.handlePayload(
        json({'type': 'collector_sync'}),
      );

      expect(outcome, RouteOutcome.success);
      expect(navigator.navigatedTo, contains('/collect'));
    });
  });

  group('nft_ready type', () {
    test('routes to /profile', () async {
      final outcome = await subject.handlePayload(
        json({'type': 'nft_ready', 'nftId': 'nft-storm-1'}),
      );

      expect(outcome, RouteOutcome.success);
      expect(navigator.navigatedTo, contains('/profile'));
    });

    test('emits route_success telemetry', () async {
      await subject.handlePayload(json({'type': 'nft_ready'}));

      final events = logSink.entries.map((e) => e.event).toList();
      expect(events, contains('notification.route_success'));
    });
  });

  group('safe fallback', () {
    test('null payload routes to /weather with fallback outcome', () async {
      final outcome = await subject.handlePayload(null);

      expect(outcome, RouteOutcome.fallback);
      expect(navigator.navigatedTo, contains('/weather'));
    });

    test('empty string routes to /weather with fallback', () async {
      final outcome = await subject.handlePayload('');

      expect(outcome, RouteOutcome.fallback);
      expect(navigator.navigatedTo, contains('/weather'));
    });

    test('malformed JSON routes to /weather with fallback', () async {
      final outcome = await subject.handlePayload('{not valid json}');

      expect(outcome, RouteOutcome.fallback);
      expect(navigator.navigatedTo, contains('/weather'));
    });

    test('unknown type routes to /weather with fallback', () async {
      final outcome = await subject.handlePayload(
        json({'type': 'completely_unknown_type'}),
      );

      expect(outcome, RouteOutcome.fallback);
      expect(navigator.navigatedTo, contains('/weather'));
    });

    test('emits route_fallback telemetry on malformed payload', () async {
      await subject.handlePayload('{bad json}');

      final events = logSink.entries.map((e) => e.event).toList();
      expect(events, contains('notification.open'));
      expect(events, contains('notification.route_fallback'));
      expect(events, isNot(contains('notification.route_success')));
    });

    test('emits route_fallback telemetry on unknown type', () async {
      await subject.handlePayload(json({'type': 'mystery'}));

      final warningEvents = logSink.entries
          .where((e) => e.event == 'notification.route_fallback')
          .toList();
      expect(warningEvents, isNotEmpty);
      expect(warningEvents.first.level, AppLogLevel.warning);
    });
  });

  group('telemetry', () {
    test('emits notification.open for every call', () async {
      await subject.handlePayload(json({'type': 'alert'}));
      await subject.handlePayload(null);

      final openEvents = logSink.entries
          .where((e) => e.event == 'notification.open')
          .toList();
      expect(openEvents.length, 2);
    });
  });
}
