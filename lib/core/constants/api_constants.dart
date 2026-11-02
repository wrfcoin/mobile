import 'package:flutter/foundation.dart' show kReleaseMode;

class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const String debugDefaultBaseUrl = 'http://localhost:4001/api';
  static const Set<String> placeholderHosts = {
    'api.wrfcoin.app',
    'api.wrfcoin.org',
    'api.wrfcoin.network',
    'example.com',
    'w3bstream.example.com',
  };

  static String resolveBaseUrl({
    required String configuredUrl,
    required bool releaseMode,
  }) {
    if (configuredUrl.trim().isNotEmpty) return configuredUrl.trim();
    return releaseMode ? '' : debugDefaultBaseUrl;
  }

  static String get effectiveBaseUrl =>
      resolveBaseUrl(configuredUrl: baseUrl, releaseMode: kReleaseMode);

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// DNS suffixes that never name a public host (RFC 6761/6762/8375, plus
  /// `.internal`). Mirrors scripts/validate-release-api-host.sh.
  static const Set<String> reservedSuffixes = {
    'localhost',
    'local',
    'invalid',
    'test',
    'example',
    'internal',
    'home.arpa',
  };

  static final RegExp _ldhHost = RegExp(
    r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$',
  );
  static final RegExp _numericLabel = RegExp(r'^(\d+|0x[0-9a-f]*)$');

  /// Lowercases [host] and strips one trailing dot, the absolute form of the
  /// same name (`localhost.` is `localhost`).
  static String canonicalHost(String host) {
    final lower = host.toLowerCase();
    return lower.endsWith('.') ? lower.substring(0, lower.length - 1) : lower;
  }

  /// IPv4 bytes of [host] in any inet_aton spelling the platform resolver
  /// accepts (`127.0.0.1`, `127.1`, `0x7f.1`, `0177.0.0.1`, `2130706433`), or
  /// null when [host] is not such a literal. Pure dart:core, so it also runs
  /// on web, where dart:io's InternetAddress is unavailable.
  static List<int>? _ipv4Bytes(String host) {
    final parts = host.split('.');
    if (parts.isEmpty || parts.length > 4) return null;
    final values = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part.length > 12) return null;
      final int? value;
      if (part.startsWith('0x')) {
        value = part.length == 2
            ? 0
            : int.tryParse(part.substring(2), radix: 16);
      } else if (part.length > 1 && part.startsWith('0')) {
        value = int.tryParse(part.substring(1), radix: 8);
      } else {
        value = int.tryParse(part);
      }
      if (value == null || value < 0) return null;
      values.add(value);
    }
    // All leading parts are single bytes; the last fills the remaining bytes.
    // Plain arithmetic, not shifts: web shifts are 32-bit.
    final lastBytes = 5 - values.length;
    for (final v in values.take(values.length - 1)) {
      if (v > 0xff) return null;
    }
    var scale = 1;
    for (var i = 1; i < lastBytes; i++) {
      scale *= 256;
    }
    final last = values.last;
    if (last >= scale * 256) return null;
    final bytes = values.take(values.length - 1).toList();
    for (var rest = last; scale >= 1; scale ~/= 256) {
      bytes.add(rest ~/ scale);
      rest %= scale;
    }
    return bytes;
  }

  /// Address bytes of an IP-literal [host] (canonical, unbracketed): 4 for
  /// IPv4 and for IPv4-mapped IPv6 (`::ffff:127.0.0.1`), 16 for other IPv6.
  static List<int>? _ipBytes(String host) {
    if (host.contains(':')) {
      try {
        final v6 = Uri.parseIPv6Address(host);
        final mapped =
            v6.take(10).every((b) => b == 0) &&
            v6[10] == 0xff &&
            v6[11] == 0xff;
        return mapped ? v6.sublist(12) : v6;
      } on FormatException {
        return null;
      }
    }
    return _ipv4Bytes(host);
  }

  static bool _isLocalHost(String host) {
    if (host == 'localhost') return true;
    final ip = _ipBytes(host);
    if (ip != null) {
      if (ip.length == 4) return ip[0] == 127 || ip[0] == 0;
      final allZeroButLast = ip.take(15).every((b) => b == 0);
      return allZeroButLast && (ip[15] == 0 || ip[15] == 1); // :: and ::1
    }
    // Single-label names (and unparseable IPv6 such as zone-scoped
    // `fe80::1%25en0`) never name a public host.
    if (!host.contains('.')) return true;
    return reservedSuffixes.any((s) => host == s || host.endsWith('.$s'));
  }

  /// Returns true if [url] points to a local/loopback address: `localhost`,
  /// loopback or unspecified IPs in any spelling, single-label names, or a
  /// reserved suffix. The host is canonicalized first, so `localhost.` and
  /// `LOCALHOST` count.
  static bool isLocalUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    return _isLocalHost(canonicalHost(uri.host));
  }

  /// Returns why [url] is unsafe for a release, or null when it is usable.
  /// Same policy as scripts/validate-release-api-host.sh: https and a
  /// canonical, multi-label public DNS name. DNS reachability is enforced by
  /// that release preflight before compilation.
  static String? releaseUrlProblem(String url) {
    final candidate = url.trim();
    if (candidate.isEmpty) return 'API_BASE_URL is unset';

    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'API_BASE_URL is not an absolute URL';
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return 'API_BASE_URL must use https';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'API_BASE_URL must not carry userinfo';
    }

    final host = canonicalHost(uri.host);
    if (placeholderHosts.contains(host)) {
      return 'API_BASE_URL uses placeholder host $host';
    }
    if (_isLocalHost(host)) {
      return 'API_BASE_URL uses local host $host';
    }
    if (_ipBytes(host) != null ||
        _numericLabel.hasMatch(host.split('.').last)) {
      return 'API_BASE_URL uses IP literal host $host; use a DNS name';
    }
    if (host.length > 253 || !_ldhHost.hasMatch(host)) {
      return 'API_BASE_URL has an invalid host $host';
    }
    return null;
  }

  // Wallet
  /// Public balance read (backend#30, #34): `GET /api/public/balance/0x<40
  /// hex>`, relative to [baseUrl] (which already ends in `/api`). Answers
  /// `{ address, balance, height, earned }`. [rawHex] is the 40 lowercase hex
  /// digits of the address with no prefix.
  static String publicBalance(String rawHex) => '/public/balance/0x$rawHex';

  // Proof cards
  /// Public proof card read (backend#229): `GET /api/proofs/<commit id>`,
  /// relative to [baseUrl]. [commitId] is core4's 64 lowercase hex commit id.
  static String proofCard(String commitId) => '/proofs/$commitId';

  /// Chain account nonce for signing a transfer (backend#1199: owner-bound,
  /// the JWT `sub` must equal [address]). Not the auth challenge at
  /// [walletNonce].
  static String walletAccountNonce(String address) => '/wallet/$address/nonce';

  /// Wallet history (backend#1199). The backend pages by `limit` (1–100) and
  /// `offset` only; it ignores `page`.
  static String walletTransactions(
    String address, {
    int offset = 0,
    int limit = 20,
  }) => '/wallet/$address/transactions?limit=$limit&offset=$offset';
  static const String walletSend = '/wallet/send';
  static const String walletSendPrivate = '/wallet/send-private';
  static const String walletStealthAddress = '/privacy/stealth-address';
  static const String walletEstimateGas = '/wallet/estimate-gas';
  static const String gasSponsor = '/gas/sponsor';
  static const String submitUserOp = '/chain/submit-userop';

  // Carbon lottery
  static String carbonLotteryDashboard(String walletAddress) =>
      '/carbon-lottery/dashboard/$walletAddress';
  static const String carbonLotteryDeposit = '/carbon-lottery/deposit';
  static const String carbonLotteryWithdraw = '/carbon-lottery/withdraw';

  // Wallet auth
  static String walletNonce(String address) => '/auth/nonce/$address';
  static const String walletLogin = '/auth/wallet-login';
  static const String authRefresh = '/auth/refresh';

  // Testnet faucet onboarding (backend: server/routes/onboarding-routes.ts,
  // mounted at /api/onboarding). Base URL already includes /api, so paths are
  // relative to that mount point.
  static const String faucetChallenge = '/onboarding/faucet/challenge';
  static const String faucetClaim = '/onboarding/faucet/claim';

  // Referral / invite onboarding
  static const String referralGenerate = '/referrals/generate';
  static const String referralActivate = '/referrals/activate';
  static String referralStats(String walletAddress) =>
      '/referrals/stats/$walletAddress';

  // Governance
  static const String proposals = '/governance/proposals';
  static String proposal(String id) => '/governance/proposals/$id';
  static String vote(String id) => '/governance/proposals/$id/vote';

  // Oracle / Sensor
  static const String oracleSubmitData = '/oracle/submit-data';
  static const String oracleSubmitDataPrepare = '/oracle/submit-data/prepare';
  static const String mobileStationChallenge =
      '/weather/stations/mobile/challenge';
  static const String mobileStationRegister = '/weather/stations/mobile';
  static const String sensorReading = '/sensors/reading';

  // Weather
  // Location-keyed routes take a CoarseLocation.pathSegment ("lat,lon" at
  // 0.1°), never a device fix or a placeholder like 'local'.
  static String weatherAlerts(String location) => '/weather/alerts/$location';
  static String weatherRealtime(String stationId) =>
      '/storage/weather/realtime/$stationId';
  static String weatherForecast(String location) =>
      '/weather/forecast/$location';
  static String weatherCurrent(String location) => '/weather/current/$location';

  /// Query for [weatherForecast]'s hourly periods: the backend reads
  /// `type=hourly` and returns `days * 24` NOAA hourly periods.
  static const weatherForecastHourlyQuery = {'type': 'hourly', 'days': 1};

  /// Query for [weatherForecast]'s daily periods. The backend passes `days`
  /// on as a count of NOAA 12-hour periods, so 14 is seven days.
  static const weatherForecastDailyQuery = {'days': 14};

  // Achievements
  static String achievements(String userId) => '/achievement/$userId';

  // Rewards
  static String claimReward(String achievementId) =>
      '/v1/rewards/claim/$achievementId';
  static const String rewardHistory = '/v1/rewards/history';

  // Stations
  static const String oracleStations = '/oracle/stations';
  static const String weatherStations = '/weather/stations';

  // Operator profiles
  static String operatorProfile(String walletAddress) =>
      '/operators/$walletAddress/profile';

  // Leaderboard — weather contribution leaderboard at /api/weather/leaderboard
  static const String leaderboard = '/weather/leaderboard';

  // Coverage
  static const String coverageZones = '/weather/coverage-zones';

  // Weather NFT portfolio
  // TODO(#34): wire up when backend implements GET /nft/portfolio/:userId
  static String nftPortfolio(String userId) => '/nft/portfolio/$userId';
  // TODO(#34): wire up when backend implements POST /nft/claim
  static const String nftClaim = '/nft/claim';

  // Treasury
  static const String treasury = '/governance/treasury';

  // WRF model forecast — real output from the IPFS pipeline.
  static String wrfForecast(String location) =>
      '/v1/weather/wrf-forecast/$location';

  // Friend challenges (backend#249 challenge-routes.ts, mounted at /api/challenges;
  // base URL already ends in /api). Every call needs the wallet login token the
  // shared ApiClient attaches; counts come from chain readings on the server.
  static const String challenges = '/challenges';
  static const String challengesJoin = '/challenges/join';
  static const String challengesSync = '/challenges/sync';

  // Free-play forecast duels (backend duel-routes.ts). The board, one duel and a
  // record hand-in need no login; open, accept and link need the wallet token.
  static const String duels = '/duels';
  static String duel(String id) => '/duels/$id';
  static String duelAccept(String id) => '/duels/$id/accept';
  static String duelForecast(String id) => '/duels/$id/forecast';
  static String duelRecord(String id) => '/duels/$id/record';

  // Station calibration certificates (backend calibration-certificate-routes.ts).
  // Public read; the edge admits only the alias form, with no query.
  static String calibrationCertificate(String alias) =>
      '/calibration-certificates/station/$alias';
}
