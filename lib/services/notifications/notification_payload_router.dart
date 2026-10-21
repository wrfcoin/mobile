import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../observability/app_logger.dart';

/// Thin navigation seam so the router can be swapped in tests without
/// subclassing [GoRouter] (which uses a factory constructor).
abstract class AppNavigator {
  void go(String location, {Object? extra});
}

/// Production adapter that delegates to [GoRouter].
class GoRouterNavigator implements AppNavigator {
  const GoRouterNavigator(this._router);

  final GoRouter _router;

  @override
  void go(String location, {Object? extra}) =>
      _router.go(location, extra: extra);
}

/// Known push notification types.
enum PushNotificationType {
  proposal,
  alert,
  walletTx,
  collectorSync,
  nftReady,
  unknown,
}

/// Result of a routing attempt.
enum RouteOutcome { success, fallback }

/// Routes an incoming push-notification payload to the correct in-app screen.
///
/// On success emits `notification.route_success`; on fallback (unknown or
/// malformed payload) navigates to `/weather` and emits
/// `notification.route_fallback`.
class NotificationPayloadRouter {
  const NotificationPayloadRouter({
    required this._router,
    required this._logger,
  });

  final AppNavigator _router;
  final AppLogger _logger;

  /// Call this when the user taps a notification.
  ///
  /// [payloadJson] is the raw payload string attached to the notification.
  Future<RouteOutcome> handlePayload(String? payloadJson) async {
    _logger.info(
      'notification.open',
      fields: <String, dynamic>{'hasPayload': payloadJson != null},
    );

    final payload = _parse(payloadJson);
    if (payload == null) {
      return _fallback(reason: 'unparseable_payload');
    }

    final type = _resolveType(payload['type'] as String?);
    switch (type) {
      case PushNotificationType.proposal:
        final id = payload['proposalId'] as String?;
        _router.go('/govern${id != null ? '?proposalId=$id' : ''}');
        _emitSuccess(type, payload);
        return RouteOutcome.success;

      case PushNotificationType.alert:
        _router.go('/weather/alerts');
        _emitSuccess(type, payload);
        return RouteOutcome.success;

      case PushNotificationType.walletTx:
        _router.go('/wallet');
        _emitSuccess(type, payload);
        return RouteOutcome.success;

      case PushNotificationType.collectorSync:
        _router.go('/collect');
        _emitSuccess(type, payload);
        return RouteOutcome.success;

      case PushNotificationType.nftReady:
        _router.go('/profile');
        _emitSuccess(type, payload);
        return RouteOutcome.success;

      case PushNotificationType.unknown:
        return _fallback(
          reason: 'unknown_type',
          fields: <String, dynamic>{'type': payload['type']},
        );
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Map<String, dynamic>? _parse(String? payloadJson) {
    if (payloadJson == null || payloadJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  PushNotificationType _resolveType(String? raw) {
    switch (raw) {
      case 'proposal':
        return PushNotificationType.proposal;
      case 'alert':
        return PushNotificationType.alert;
      case 'wallet_tx':
        return PushNotificationType.walletTx;
      case 'collector_sync':
        return PushNotificationType.collectorSync;
      case 'nft_ready':
        return PushNotificationType.nftReady;
      default:
        return PushNotificationType.unknown;
    }
  }

  void _emitSuccess(PushNotificationType type, Map<String, dynamic> payload) {
    _logger.info(
      'notification.route_success',
      fields: <String, dynamic>{'notificationType': type.name},
    );
  }

  RouteOutcome _fallback({
    required String reason,
    Map<String, dynamic>? fields,
  }) {
    _router.go('/weather');
    _logger.warning(
      'notification.route_fallback',
      fields: <String, dynamic>{'reason': reason, ...?fields},
    );
    return RouteOutcome.fallback;
  }
}

final notificationPayloadRouterProvider = Provider<NotificationPayloadRouter>((
  ref,
) {
  return NotificationPayloadRouter(
    router: GoRouterNavigator(ref.watch(appRouterProvider)),
    logger: ref.watch(appLoggerProvider),
  );
});
