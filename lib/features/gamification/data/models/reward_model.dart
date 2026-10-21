/// Result of a successful claim, including an already-claimed acknowledgement.
class RewardResult {
  /// True for a repeat claim. The minimal acknowledgement has no payout fields;
  /// a full repeat response can retain the original reward and transaction.
  final bool alreadyClaimed;
  final String? rewardId;
  final double? wrfAmount;
  final String? txHash;

  const RewardResult({
    required this.rewardId,
    required this.wrfAmount,
    this.txHash,
    this.alreadyClaimed = false,
  });

  const RewardResult.alreadyClaimed()
    : alreadyClaimed = true,
      rewardId = null,
      wrfAmount = null,
      txHash = null;

  factory RewardResult.fromJson(Map<String, dynamic> json) {
    return RewardResult(
      rewardId: json['rewardId']?.toString() ?? json['id']?.toString() ?? '',
      wrfAmount: _parseDouble(json['wrfAmount'] ?? json['amount']) ?? 0.0,
      txHash: json['txHash']?.toString(),
      alreadyClaimed: json['alreadyClaimed'] == true,
    );
  }
}

/// An entry in the user's reward claim history.
class RewardHistoryEntry {
  final String achievementId;
  final double wrfAmount;
  final DateTime claimedAt;
  final String? txHash;

  const RewardHistoryEntry({
    required this.achievementId,
    required this.wrfAmount,
    required this.claimedAt,
    this.txHash,
  });

  factory RewardHistoryEntry.fromJson(Map<String, dynamic> json) {
    final claimedAtRaw =
        json['claimedAt']?.toString() ?? json['timestamp']?.toString() ?? '';
    return RewardHistoryEntry(
      achievementId:
          json['achievementId']?.toString() ??
          json['achievement_id']?.toString() ??
          '',
      wrfAmount: _parseDouble(json['wrfAmount'] ?? json['amount']) ?? 0.0,
      claimedAt: DateTime.tryParse(claimedAtRaw) ?? DateTime.now(),
      txHash: json['txHash']?.toString(),
    );
  }
}

double? _parseDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
