List<dynamic> unwrapListPayload(dynamic payload) {
  final unwrapped = unwrapPayload(payload);
  if (unwrapped is List) return unwrapped;
  if (unwrapped is Map<String, dynamic>) {
    final candidates = [
      unwrapped['stations'],
      unwrapped['items'],
      unwrapped['results'],
    ];
    for (final candidate in candidates) {
      if (candidate is List) return candidate;
    }
  }
  return const [];
}

Map<String, dynamic> unwrapMapPayload(dynamic payload) {
  final unwrapped = unwrapPayload(payload);
  if (unwrapped is Map<String, dynamic>) return unwrapped;
  return const {};
}

dynamic unwrapPayload(dynamic payload) {
  if (payload is Map<String, dynamic>) {
    final data = payload['data'];
    if (data != null) return data;
  }
  return payload;
}
