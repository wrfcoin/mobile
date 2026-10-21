class LeaderboardEntry {
  final int rank;
  final String name;
  final String score;
  final String metricLabel;
  final String subtitle;

  /// True when the server marks this row as the signed-in wallet's own.
  final bool isYou;

  const LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.score,
    this.metricLabel = 'score',
    this.subtitle = '',
    this.isYou = false,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json, int index) {
    if (json.containsKey('earningsBaseUnits')) {
      return LeaderboardEntry.fromEarningsJson(json);
    }
    final scoreSource =
        json['readings'] ??
        json['completedAchievements'] ??
        json['score'] ??
        json['totalTokensEarned'] ??
        0;
    final badges = json['badges'];

    return LeaderboardEntry(
      rank: (json['rank'] as num?)?.toInt() ?? index + 1,
      name:
          json['name']?.toString() ??
          json['username']?.toString() ??
          _shortAddress(json['userId']?.toString()) ??
          'Unknown',
      score: _stringifyScore(scoreSource),
      metricLabel: _metricLabelFor(json),
      subtitle:
          json['region']?.toString() ??
          json['category']?.toString() ??
          (badges is List && badges.isNotEmpty
              ? '${badges.length} badges'
              : ''),
    );
  }

  /// Strict chain-earnings board row (backend#1457): rank and a valid
  /// `earningsBaseUnits` are required. The amount is an exact decimal
  /// string of base units; it is parsed as a [BigInt] and never touches a
  /// double. An amount that cannot be proven is a [FormatException], so a bad
  /// row fails the whole board instead of rendering as zero.
  ///
  /// The address is shown exactly as served (short for anonymous rows, full
  /// only on the server-marked own row); it is never built client-side.
  factory LeaderboardEntry.fromEarningsJson(Map<String, dynamic> json) {
    final rank = json['rank'];
    if (rank is! num) throw FormatException('Invalid rank', rank);
    return LeaderboardEntry(
      rank: rank.toInt(),
      name: json['displayName']?.toString() ?? 'Unknown',
      score: formatBaseUnits(json['earningsBaseUnits']),
      metricLabel: 'WRF',
      subtitle: json['walletAddress']?.toString() ?? '',
      isYou: json['isYou'] == true,
    );
  }

  static const int _decimals = 8;

  /// Formats an exact base-unit decimal string as WRF with 8 decimals.
  static String formatBaseUnits(Object? raw) {
    if (raw is! String || !RegExp(r'^\d+$').hasMatch(raw)) {
      throw FormatException('Invalid earningsBaseUnits', raw);
    }
    final value = BigInt.parse(raw);
    final scale = BigInt.from(10).pow(_decimals);
    final whole = value ~/ scale;
    final frac = (value % scale).toString().padLeft(_decimals, '0');
    return '$whole.$frac';
  }

  static String _metricLabelFor(Map<String, dynamic> json) {
    if (json['metricLabel'] != null) {
      return json['metricLabel'].toString();
    }
    if (json.containsKey('readings')) return 'readings';
    if (json.containsKey('completedAchievements')) return 'achievements';
    if (json.containsKey('totalTokensEarned')) return 'WRF';
    return 'score';
  }

  static String _stringifyScore(dynamic value) {
    if (value == null) return '0';
    if (value is num) {
      return value % 1 == 0 ? value.toInt().toString() : value.toString();
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return '0';
    final match = RegExp(r'-?\d+(?:\.\d+)?')
        .firstMatch(raw.replaceAll(',', ''));
    return match?.group(0) ?? raw;
  }

  static String? _shortAddress(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length <= 12) return value;
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }
}
