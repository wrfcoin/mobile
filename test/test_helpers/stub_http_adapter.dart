import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answers every request from [answer] with (status, JSON body or raw text).
/// Throws a connection error when [answer] returns null.
class StubHttpAdapter implements HttpClientAdapter {
  StubHttpAdapter(this.answer);

  final (int, Object?)? Function(RequestOptions options) answer;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = answer(options);
    if (reply == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final (status, body) = reply;
    final isText = body is String;
    return ResponseBody.fromString(
      isText ? body : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [isText ? 'text/html' : 'application/json'],
      },
    );
  }
}

Dio stubDio(StubHttpAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://test.invalid/api'))
      ..httpClientAdapter = adapter;
