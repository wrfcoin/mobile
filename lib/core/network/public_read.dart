import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

/// The outcome of one public, read-only API call. Mirrors the website's
/// `publicGet`, so a screen can say exactly what happened and never has to
/// fall back on a made-up value.
sealed class PublicRead<T> {
  const PublicRead();
}

class PublicLoaded<T> extends PublicRead<T> {
  const PublicLoaded(this.data);
  final T data;
}

/// HTTP 404: this server does not offer the feature (or that item).
class PublicNotFound<T> extends PublicRead<T> {
  const PublicNotFound();
}

/// HTTP 429.
class PublicRateLimited<T> extends PublicRead<T> {
  const PublicRateLimited();
}

/// Offline, a server error, or an answer that was not the expected JSON.
class PublicUnavailable<T> extends PublicRead<T> {
  const PublicUnavailable({this.statusCode});
  final int? statusCode;
}

/// GETs [path] and parses the JSON object it answers. Never throws: anything
/// [parse] cannot use (an HTML fallback page, say) is [PublicUnavailable].
Future<PublicRead<T>> readPublicJson<T>(
  Dio dio,
  String path,
  T Function(Map<String, dynamic> json) parse,
) async {
  try {
    final response = await dio.get<dynamic>(path);
    final data = response.data;
    if (data is! Map) return PublicUnavailable(statusCode: response.statusCode);
    return PublicLoaded(parse(Map<String, dynamic>.from(data)));
  } on DioException catch (error) {
    return switch (error.response?.statusCode) {
      404 => const PublicNotFound(),
      429 => const PublicRateLimited(),
      final status => PublicUnavailable(statusCode: status),
    };
  } on FormatException {
    return const PublicUnavailable();
  } on TypeError {
    return const PublicUnavailable();
  }
}

// Field readers for API answers: a missing or malformed value is null, never
// a default number.

int? jsonInt(Object? value) {
  if (value is int) return value;
  if (value is String && RegExp(r'^\d{1,15}$').hasMatch(value)) {
    return int.parse(value);
  }
  return null;
}

double? jsonDouble(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

String? jsonText(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

Map<String, dynamic>? jsonObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> jsonObjects(Object? value) => value is List
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : const [];

/// Shown for a value the server did not give.
const String publicUnknown = '—';

/// A count from an int or a digit string, grouped; [publicUnknown] otherwise.
String publicCount(Object? value) {
  final digits = switch (value) {
    final int n when n >= 0 => '$n',
    final String s when RegExp(r'^\d{1,39}$').hasMatch(s) => s,
    _ => null,
  };
  if (digits == null) return publicUnknown;
  return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// An API timestamp in the phone's time zone; [publicUnknown] when absent.
String publicWhen(String? iso, {bool withTime = true}) {
  final parsed = iso == null ? null : DateTime.tryParse(iso);
  if (parsed == null) return iso ?? publicUnknown;
  final format = withTime ? DateFormat('MMM d, y, h:mm a') : DateFormat.yMMMd();
  return format.format(parsed.toLocal());
}
