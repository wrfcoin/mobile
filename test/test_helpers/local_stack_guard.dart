/// Hosts the local-stack E2E may talk to. It mines blocks with an operator
/// token, so it must never reach a real chain (mobile#286, review of #301).
const Set<String> loopbackHosts = {'127.0.0.1', 'localhost', '::1'};

/// Why [url] is not an http(s) URL on a loopback host, or null when it is.
///
/// Deliberately narrower than `ApiConstants.isLocalUrl`: `0.0.0.0`, `*.local`
/// and LAN addresses are refused, and so are userinfo tricks such as
/// `http://127.0.0.1@host.example`, because only the parsed host counts.
String? nonLoopbackReason(String name, String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '$name is not an absolute URL: "$url"';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return '$name must be http(s), got "${uri.scheme}"';
  }
  if (uri.userInfo.isNotEmpty) {
    return '$name must not carry userinfo: "$url"';
  }
  final host = uri.host.toLowerCase();
  if (!loopbackHosts.contains(host)) {
    return '$name must point at 127.0.0.1, localhost or ::1, not "$host". '
        'This E2E mines with an operator token and must never reach a real chain.';
  }
  return null;
}
