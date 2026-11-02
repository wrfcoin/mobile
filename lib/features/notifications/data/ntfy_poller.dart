import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/notifications/push_service.dart';
import 'payout_notifications.dart';

/// A hard-to-guess topic: anyone who knows an ntfy topic can read it.
String suggestNtfyTopic([Random? random]) {
  final source = random ?? Random.secure();
  final hex = List.generate(
    8,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'wrfcoin-pay-$hex';
}

/// This phone's own topic and how far it has read. SharedPreferences, because
/// the Workmanager isolate reads it too. The topic only unlocks payout notices
/// for public chain addresses, so it needs no key-grade storage.
class NtfyDeviceStore {
  const NtfyDeviceStore();

  static const _topicKey = 'payout_ntfy_topic';
  static const _serverKey = 'payout_ntfy_server';
  static const _sinceKey = 'payout_ntfy_since';

  Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  Future<String?> topic() async => (await _prefs()).getString(_topicKey);
  Future<String?> server() async => (await _prefs()).getString(_serverKey);
  Future<String?> since() async => (await _prefs()).getString(_sinceKey);

  Future<void> saveSince(String since) async {
    await (await _prefs()).setString(_sinceKey, since);
  }

  Future<void> save({
    required String topic,
    required String server,
    required String since,
  }) async {
    final prefs = await _prefs();
    await prefs.setString(_topicKey, topic);
    await prefs.setString(_serverKey, server);
    await prefs.setString(_sinceKey, since);
  }

  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_topicKey);
    await prefs.remove(_serverKey);
    await prefs.remove(_sinceKey);
  }
}

typedef ShowPayoutNotice = Future<void> Function({
  required int id,
  required String title,
  required String body,
});

/// Reads this phone's topic from ntfy and shows what arrived as local
/// notifications, so no ntfy app, account or paid push service is needed. This
/// uses its own plain Dio: the wallet session never goes to the ntfy server.
class NtfyPoller {
  NtfyPoller({required this.store, required this.show, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: false,
            ),
          );

  final NtfyDeviceStore store;
  final ShowPayoutNotice show;
  final Dio _dio;

  /// A burst after days offline should not flood the shade.
  static const maxShownPerPoll = 5;

  /// How many notices were shown. Network errors are not thrown: the next
  /// periodic check reads from the same place, so nothing is lost.
  Future<int> pollOnce() async {
    final topic = await store.topic();
    final server = await store.server();
    final since = await store.since();
    if (topic == null || server == null || since == null) return 0;
    if (!ntfyTopicPattern.hasMatch(topic) || !server.startsWith('https://')) {
      return 0;
    }
    final Response<String> response;
    try {
      response = await _dio.get<String>(
        '$server/$topic/json',
        queryParameters: {'poll': '1', 'since': since},
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException {
      return 0;
    }
    final messages = parseNtfyMessages(response.data ?? '');
    if (messages.isEmpty) return 0;
    final recent = messages.length > maxShownPerPoll
        ? messages.sublist(messages.length - maxShownPerPoll)
        : messages;
    for (final message in recent) {
      await show(
        id: message.id.hashCode & 0x7fffffff,
        title: message.title,
        body: message.body,
      );
    }
    await store.saveSince(messages.last.id);
    return recent.length;
  }
}

class NtfyMessage {
  const NtfyMessage({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;
}

/// ntfy's poll answer: one JSON object per line. Only `message` events count
/// (`open` and `keepalive` carry nothing), and a line it cannot read is skipped.
List<NtfyMessage> parseNtfyMessages(String body) {
  final messages = <NtfyMessage>[];
  for (final line in const LineSplitter().convert(body)) {
    if (line.trim().isEmpty) continue;
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (json is! Map || json['event'] != 'message') continue;
    final id = json['id'];
    final text = json['message'];
    if (id is! String || id.isEmpty || text is! String) continue;
    final title = json['title'];
    messages.add(
      NtfyMessage(
        id: id,
        title: title is String && title.isNotEmpty ? title : 'WRFCoin',
        body: text,
      ),
    );
  }
  return messages;
}

/// The Workmanager entry: one check of this phone's topic.
Future<void> pollPayoutNotificationsInBackground() async {
  final push = PushService();
  await NtfyPoller(
    store: const NtfyDeviceStore(),
    show: push.showPayoutNotification,
  ).pollOnce();
}
