enum CarbonLotteryAction { deposit, withdraw }

class CarbonLotterySnapshot {
  final int epoch;
  final DateTime? epochEndsAt;
  final String jackpotCredits;
  final String projectedYieldCredits;
  final String totalDepositedCredits;
  final String userDepositCredits;
  final bool principalProtected;
  final bool preview;
  final List<CarbonLotteryHistoryEntry> history;

  const CarbonLotterySnapshot({
    required this.epoch,
    required this.epochEndsAt,
    required this.jackpotCredits,
    required this.projectedYieldCredits,
    required this.totalDepositedCredits,
    required this.userDepositCredits,
    required this.principalProtected,
    required this.preview,
    required this.history,
  });

  factory CarbonLotterySnapshot.fromJson(Map<String, dynamic> json) {
    final source = _readNestedMap(json, const [
      'lottery',
      'carbonLottery',
      'dashboard',
    ]);

    return CarbonLotterySnapshot(
      epoch: _readInt(
        source['epoch'] ?? source['currentEpoch'] ?? source['epochNumber'],
      ),
      epochEndsAt: _readDate(
        source['epochEndsAt'] ?? source['endsAt'] ?? source['drawAt'],
      ),
      jackpotCredits: _readAmount(
        source['jackpotCredits'] ?? source['jackpot'] ?? source['prizePool'],
      ),
      projectedYieldCredits: _readAmount(
        source['projectedYieldCredits'] ??
            source['projectedYield'] ??
            source['yield'],
      ),
      totalDepositedCredits: _readAmount(
        source['totalDepositedCredits'] ??
            source['totalDeposited'] ??
            source['tvl'],
      ),
      userDepositCredits: _readAmount(
        source['userDepositCredits'] ??
            source['userDeposit'] ??
            source['principal'],
      ),
      principalProtected:
          _readBool(source['principalProtected'] ?? source['principalSafe']) ??
          (throw StateError('Missing principal protection disclosure')),
      preview: _readBool(source['preview'] ?? source['stubbed']) ?? false,
      history: _readHistory(
        source['history'] ??
            source['recentHistory'] ??
            source['recentWinners'] ??
            source['events'],
      ),
    );
  }

  CarbonLotterySnapshot copyWith({
    String? userDepositCredits,
    List<CarbonLotteryHistoryEntry>? history,
  }) {
    return CarbonLotterySnapshot(
      epoch: epoch,
      epochEndsAt: epochEndsAt,
      jackpotCredits: jackpotCredits,
      projectedYieldCredits: projectedYieldCredits,
      totalDepositedCredits: totalDepositedCredits,
      userDepositCredits: userDepositCredits ?? this.userDepositCredits,
      principalProtected: principalProtected,
      preview: preview,
      history: history ?? this.history,
    );
  }
}

class CarbonLotteryHistoryEntry {
  final String id;
  final int epoch;
  final String label;
  final String amountCredits;
  final String walletAddress;
  final DateTime? timestamp;
  final String type;

  const CarbonLotteryHistoryEntry({
    required this.id,
    required this.epoch,
    required this.label,
    required this.amountCredits,
    required this.walletAddress,
    required this.timestamp,
    required this.type,
  });

  factory CarbonLotteryHistoryEntry.fromJson(Map<String, dynamic> json) {
    return CarbonLotteryHistoryEntry(
      id: (json['id'] ?? json['txHash'] ?? json['hash'] ?? '').toString(),
      epoch: _readInt(json['epoch'] ?? json['epochNumber']),
      label: (json['label'] ?? json['title'] ?? json['kind'] ?? 'Draw result')
          .toString(),
      amountCredits: _readAmount(json['amountCredits'] ?? json['amount']),
      walletAddress:
          (json['walletAddress'] ??
                  json['winner'] ??
                  json['recipient'] ??
                  json['address'] ??
                  '')
              .toString(),
      timestamp: _readDate(json['timestamp'] ?? json['createdAt']),
      type: (json['type'] ?? json['kind'] ?? 'winner').toString(),
    );
  }
}

class CarbonLotteryActionRequest {
  final String requestId;
  final CarbonLotteryAction action;
  final String walletAddress;
  final String amountCredits;
  final String status;
  final bool preview;

  const CarbonLotteryActionRequest({
    required this.requestId,
    required this.action,
    required this.walletAddress,
    required this.amountCredits,
    required this.status,
    required this.preview,
  });

  factory CarbonLotteryActionRequest.fromJson(
    Map<String, dynamic> json, {
    required CarbonLotteryAction action,
    required String walletAddress,
    required String amountCredits,
  }) {
    final source = _readNestedMap(json, const [
      'request',
      'transaction',
      'data',
    ]);

    final requestId =
        (source['requestId'] ??
                source['id'] ??
                source['txHash'] ??
                source['hash'] ??
                '')
            .toString()
            .trim();
    final status = (source['status'] ?? '').toString().trim();
    if (requestId.isEmpty ||
        status.isEmpty ||
        (_readBool(source['preview'] ?? source['stubbed']) ?? false)) {
      throw StateError('Lottery service did not acknowledge this request');
    }

    return CarbonLotteryActionRequest(
      requestId: requestId,
      action: action,
      walletAddress:
          (source['walletAddress'] ?? source['from'] ?? walletAddress)
              .toString(),
      amountCredits: _readAmount(
        source['amountCredits'] ?? source['amount'] ?? amountCredits,
      ),
      status: status,
      preview: _readBool(source['preview'] ?? source['stubbed']) ?? false,
    );
  }
}

Map<String, dynamic> _readNestedMap(
  Map<String, dynamic> json,
  List<String> nestedKeys,
) {
  dynamic current = json['data'] ?? json;
  if (current is! Map) return json;

  var map = Map<String, dynamic>.from(current);
  for (final key in nestedKeys) {
    final value = map[key];
    if (value is Map) {
      map = Map<String, dynamic>.from(value);
      break;
    }
  }

  return map;
}

List<CarbonLotteryHistoryEntry> _readHistory(dynamic value) {
  if (value is! List) return const <CarbonLotteryHistoryEntry>[];

  return value
      .whereType<Map>()
      .map(
        (entry) => CarbonLotteryHistoryEntry.fromJson(
          Map<String, dynamic>.from(entry),
        ),
      )
      .toList(growable: false);
}

String _readAmount(dynamic value) {
  if (value == null) throw StateError('Missing lottery amount');

  final raw = value.toString().trim().replaceAll(',', '');
  final match = RegExp(r'^(\d+(?:\.\d+)?)(?:\s+credits)?$').firstMatch(raw);
  if (match == null) throw StateError('Invalid lottery amount');
  return match.group(1)!;
}

int _readInt(dynamic value) {
  final number = int.tryParse(value?.toString() ?? '');
  if (number == null || number < 0) throw StateError('Invalid lottery epoch');
  return number;
}

DateTime? _readDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

bool? _readBool(dynamic value) {
  if (value is bool) return value;
  if (value == null) return null;
  final normalized = value.toString().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return null;
}
