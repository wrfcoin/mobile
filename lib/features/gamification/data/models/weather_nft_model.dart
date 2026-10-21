/// NFT badge types issued for weather contribution milestones.
enum NftType { streak, stormChaser }

/// Earned/claimable/locked status from the backend.
enum NftStatus { owned, claimable, locked }

/// Rarity tier of the NFT.
enum NftRarity { common, rare, epic, legendary }

/// A weather-contribution NFT (streak or storm-chaser badge).
class WeatherNftModel {
  const WeatherNftModel({
    required this.id,
    required this.type,
    required this.tier,
    required this.rarity,
    required this.status,
    required this.name,
    required this.description,
    this.earnedAt,
  });

  final String id;
  final NftType type;

  /// Achievement tier (bronze / silver / gold / platinum).
  final String tier;

  final NftRarity rarity;
  final NftStatus status;
  final String name;
  final String description;

  /// ISO-8601 string of when the badge was earned; null if not yet owned.
  final String? earnedAt;

  bool get isOwned => status == NftStatus.owned;
  bool get isClaimable => status == NftStatus.claimable;

  factory WeatherNftModel.fromJson(Map<String, dynamic> json) {
    return WeatherNftModel(
      id: json['id']?.toString() ?? json['nftId']?.toString() ?? '',
      type: _parseType(json['type']?.toString()),
      tier: json['tier']?.toString() ?? 'bronze',
      rarity: _parseRarity(json['rarity']?.toString()),
      status: _parseStatus(json['status']?.toString()),
      name: json['name']?.toString() ?? json['title']?.toString() ?? 'Badge',
      description: json['description']?.toString() ?? '',
      earnedAt: json['earnedAt']?.toString() ?? json['earnDate']?.toString(),
    );
  }

  static NftType _parseType(String? raw) => switch (raw) {
    'storm_chaser' || 'stormChaser' => NftType.stormChaser,
    _ => NftType.streak,
  };

  static NftRarity _parseRarity(String? raw) => switch (raw) {
    'rare' => NftRarity.rare,
    'epic' => NftRarity.epic,
    'legendary' => NftRarity.legendary,
    _ => NftRarity.common,
  };

  static NftStatus _parseStatus(String? raw) => switch (raw) {
    'claimable' => NftStatus.claimable,
    'locked' => NftStatus.locked,
    _ => NftStatus.owned,
  };
}
