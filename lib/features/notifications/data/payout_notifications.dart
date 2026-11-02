import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../services/api/api_client.dart';

/// Payout notifications (backend payout-notification-routes.ts): "get told
/// when your node or station is paid". A subscription is an address plus an
/// ntfy topic. No email, no name: nothing personal is sent or kept.
final RegExp ntfyTopicPattern = RegExp(r'^[A-Za-z0-9_-]{12,64}$');

class NotificationConfig {
  const NotificationConfig({
    required this.enabled,
    required this.checkEveryMinutes,
    required this.ntfyServer,
  });

  final bool enabled;
  final int? checkEveryMinutes;

  /// The ntfy server the backend delivers to, or null when it has none. Only
  /// an https server counts: this app reads the topic from it.
  final String? ntfyServer;

  factory NotificationConfig.fromJson(Object? body) {
    if (body is! Map || body['enabled'] is! bool) {
      throw const FormatException(
        'Notification config has an unexpected shape',
      );
    }
    final ntfy = body['ntfy'];
    final server = ntfy is Map && ntfy['available'] == true
        ? ntfy['server']
        : null;
    final minutes = body['checkEveryMinutes'];
    return NotificationConfig(
      enabled: body['enabled'] as bool,
      checkEveryMinutes: minutes is num ? minutes.toInt() : null,
      ntfyServer: server is String && server.startsWith('https://')
          ? server
          : null,
    );
  }
}

class NotificationSubscription {
  const NotificationSubscription({
    required this.id,
    required this.channel,
    required this.label,
    this.lastDeliveredAt,
  });

  final String id;

  /// `ntfy` or `webpush`. A browser's push subscription is listed but this app
  /// cannot act on it beyond removing it.
  final String channel;

  /// The topic for ntfy; the push service's host for a browser.
  final String label;
  final DateTime? lastDeliveredAt;

  factory NotificationSubscription.fromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    final channel = json['channel'];
    if (id is! String || channel is! String) {
      throw const FormatException('Subscription has no id or channel');
    }
    return NotificationSubscription(
      id: id,
      channel: channel,
      label: json['label']?.toString() ?? '',
      lastDeliveredAt: DateTime.tryParse(
        json['lastDeliveredAt']?.toString() ?? '',
      ),
    );
  }
}

final payoutNotificationRepositoryProvider =
    Provider<PayoutNotificationRepository>((ref) {
      final client = ref.watch(apiClientProvider);
      return ApiPayoutNotificationRepository(
        client.dio,
        signIn: client.signInNow,
        hasSession: client.ensureWalletSession,
      );
    });

abstract class PayoutNotificationRepository {
  Future<Either<Failure, NotificationConfig>> config();

  /// True with a live wallet session. Never prompts for the wallet key.
  Future<bool> hasSession();

  /// The explicit sign-in, from a user's tap.
  Future<bool> signIn();

  Future<Either<Failure, List<NotificationSubscription>>> list(String address);
  Future<Either<Failure, NotificationSubscription>> subscribeTopic(
    String address,
    String topic,
  );
  Future<Either<Failure, Unit>> remove(String id);

  /// True when the server handed the test to the channel.
  Future<Either<Failure, bool>> sendTest(String id);

  /// Stops a topic with no login: holding the topic is the proof.
  Future<Either<Failure, Unit>> stopTopic(String topic);
}

class ApiPayoutNotificationRepository implements PayoutNotificationRepository {
  ApiPayoutNotificationRepository(
    this._dio, {
    required this._signIn,
    required this._hasSession,
  });

  final Dio _dio;
  final Future<bool> Function() _signIn;
  final Future<bool> Function() _hasSession;

  static final _write = Options(extra: {'noRetry': true});

  Failure _failure(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final code = body is Map && body['error'] is Map
        ? (body['error'] as Map)['code']?.toString()
        : null;
    if (status == null) return const NetworkFailure();
    if (status == 401 || code == 'WALLET_LOGIN_REQUIRED') {
      return const AuthFailure(
        'Your wallet session ended. Sign in again to change notifications.',
      );
    }
    if (code == 'WALLET_MISMATCH') {
      return const AuthFailure('The signed-in wallet is not this address.');
    }
    if (code == 'NOTIFICATIONS_DISABLED' || (status == 404 && code == null)) {
      return const NotAvailableFailure(
        'Payout notifications are not switched on for this network.',
        statusCode: 404,
      );
    }
    if (code == 'TOO_MANY_SUBSCRIPTIONS') {
      return const ValidationFailure(
        'This address already has the maximum of 10 devices or topics.',
      );
    }
    if (code == 'CHANNEL_UNAVAILABLE') {
      return const ValidationFailure('ntfy is not set up on this server.');
    }
    if (code == 'TEST_COOLDOWN') {
      return const ValidationFailure('One test per minute. Try again shortly.');
    }
    if (status == 429) {
      return const ValidationFailure(
        'Too many requests. Try again in a minute.',
      );
    }
    if (status >= 400 && status < 500) {
      return const ValidationFailure(
        'That did not work. Nothing was changed; please try again.',
      );
    }
    return ServerFailure(
      'Notifications are unavailable right now.',
      statusCode: status,
    );
  }

  Future<Either<Failure, T>> _call<T>(
    Future<Response<dynamic>> Function() request,
    T Function(Object? data) parse,
  ) async {
    try {
      return Right(parse((await request()).data));
    } on DioException catch (error) {
      return Left(_failure(error));
    } on FormatException {
      return const Left(
        ServerFailure('The notification service sent an unexpected answer.'),
      );
    }
  }

  Future<Either<Failure, T>> _asWallet<T>(
    Future<Response<dynamic>> Function() request,
    T Function(Object? data) parse,
  ) async {
    if (!await _signIn()) {
      return const Left(
        AuthFailure('Sign in with your wallet first. Nothing was changed.'),
      );
    }
    return _call(request, parse);
  }

  @override
  Future<bool> hasSession() => _hasSession();

  @override
  Future<bool> signIn() => _signIn();

  @override
  Future<Either<Failure, NotificationConfig>> config() => _call(
    () => _dio.get(ApiConstants.notificationsConfig),
    NotificationConfig.fromJson,
  );

  @override
  Future<Either<Failure, List<NotificationSubscription>>> list(
    String address,
  ) => _call(() => _dio.get(ApiConstants.notificationsList(address)), (data) {
    final items = data is Map ? data['subscriptions'] : null;
    if (items is! List) {
      throw const FormatException('Answer has no subscriptions');
    }
    return items
        .whereType<Map>()
        .map(NotificationSubscription.fromJson)
        .toList(growable: false);
  });

  @override
  Future<Either<Failure, NotificationSubscription>> subscribeTopic(
    String address,
    String topic,
  ) => _asWallet(
    () => _dio.post(
      ApiConstants.notificationsSubscriptions,
      data: {'address': address, 'channel': 'ntfy', 'topic': topic},
      options: _write,
    ),
    (data) {
      final item = data is Map ? data['subscription'] : null;
      if (item is! Map) {
        throw const FormatException('Answer has no subscription');
      }
      return NotificationSubscription.fromJson(item);
    },
  );

  @override
  Future<Either<Failure, Unit>> remove(String id) => _asWallet(
    () => _dio.delete(
      ApiConstants.notificationsSubscription(id),
      options: _write,
    ),
    (_) => unit,
  );

  @override
  Future<Either<Failure, bool>> sendTest(String id) => _asWallet(
    () => _dio.post(
      ApiConstants.notificationsTest(id),
      data: const <String, dynamic>{},
      options: _write,
    ),
    (data) => data is Map && data['delivered'] == true,
  );

  @override
  Future<Either<Failure, Unit>> stopTopic(String topic) => _call(
    () => _dio.post(
      ApiConstants.notificationsUnsubscribe,
      data: {'channel': 'ntfy', 'topic': topic},
      options: _write,
    ),
    (_) => unit,
  );
}
