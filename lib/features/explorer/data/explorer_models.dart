/// Read models for the public chain explorer (backend `GET /api/explorer/summary`
/// and `GET /api/blockchain/blocks`). Every field is nullable: a missing or
/// malformed value is unknown, never defaulted to a number.
library;

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) return value.isFinite ? value.toDouble() : null;
  if (value is String) {
    // 'NaN' and 'Infinity' parse as doubles; only a finite value is a number.
    final parsed = double.tryParse(value.trim());
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}

String? _asText(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

enum ChainStatus { producing, stalled, unknown, degraded }

class ExplorerSummary {
  const ExplorerSummary({
    required this.status,
    this.height,
    this.tipAgeSeconds,
    this.blocksPerMinute,
    this.peerCount,
    this.faucetFunded,
  });

  /// Nothing known: the backend said `degraded`, or the request failed.
  const ExplorerSummary.degraded() : this(status: ChainStatus.degraded);

  final ChainStatus status;
  final int? height;
  final int? tipAgeSeconds;
  final double? blocksPerMinute;
  final int? peerCount;

  /// null means unknown, which is not the same as "not funded".
  final bool? faucetFunded;

  factory ExplorerSummary.fromJson(Map<String, dynamic> json) {
    final state = _asText(json['state']);
    if (state != 'ok') return const ExplorerSummary.degraded();
    final status = switch (_asText(json['status'])) {
      'producing' => ChainStatus.producing,
      'stalled' => ChainStatus.stalled,
      _ => ChainStatus.unknown,
    };
    final funded = json['faucetFunded'];
    return ExplorerSummary(
      status: status,
      height: _asInt(json['height']),
      tipAgeSeconds: _asInt(json['tipAgeSeconds']),
      blocksPerMinute: _asDouble(json['blocksPerMinute']),
      peerCount: _asInt(json['peerCount']),
      faucetFunded: funded is bool ? funded : null,
    );
  }
}

class ChainBlock {
  const ChainBlock({
    this.height,
    this.hash,
    this.previousHash,
    this.timestamp,
    this.transactionCount,
  });

  final int? height;
  final String? hash;
  final String? previousHash;
  final DateTime? timestamp;
  final int? transactionCount;

  factory ChainBlock.fromJson(Map<String, dynamic> json) {
    final rawTime = json['timestamp'];
    DateTime? time;
    if (rawTime is String) {
      time = DateTime.tryParse(rawTime)?.toUtc();
    } else if (rawTime is num && rawTime.isFinite) {
      final n = rawTime.toInt();
      time = DateTime.fromMillisecondsSinceEpoch(
        n < 1000000000000 ? n * 1000 : n,
        isUtc: true,
      );
    }
    return ChainBlock(
      height: _asInt(json['height']),
      hash: _asText(json['hash']),
      previousHash: _asText(json['previousHash']),
      timestamp: time,
      // The detail route reports `transactionCount` (null when unreported) beside a
      // projected `transactions` array that cannot establish a total, so an explicit
      // null stays unknown. Only the legacy list shape, which has no
      // `transactionCount` key and carries `transactions` as a number, supplies a count.
      transactionCount: json.containsKey('transactionCount')
          ? _asInt(json['transactionCount'])
          : (json['transactions'] is num ? _asInt(json['transactions']) : null),
    );
  }
}

/// The recent-blocks read: [blocks] is null when that request failed.
class ChainSnapshot {
  const ChainSnapshot({required this.summary, required this.blocks});

  final ExplorerSummary summary;
  final List<ChainBlock>? blocks;
}
