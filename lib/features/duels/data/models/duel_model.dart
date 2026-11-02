import 'dart:convert';

/// Free-play forecast duels (backend#228, #1424 duel-routes.ts). Parsing and
/// formatting only: the verdict, rewards and phases are the server's, which
/// reads them from the chain. Nothing here computes a score or a winner.
final RegExp duelIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final RegExp stationAliasPattern = RegExp(r'^st_[0-9a-f]{12}$');
final RegExp commitIdPattern = RegExp(r'^[0-9a-f]{64}$');

const String duelFreePlayNote =
    'Free play: no stakes, nothing is paid for winning. The chain judges: '
    "each forecast's own reward on chain decides.";

String duelPhaseLabel(String phase) => switch (phase) {
  'open' => 'Waiting for an opponent',
  'expired' => 'Nobody accepted',
  'committing' => 'Link forecasts before the lock',
  'waiting_for_target' => 'Locked: waiting for the target hour',
  'judging' => "Waiting for the chain's verdict",
  'resolved' => 'Decided',
  'void' => 'Void',
  _ => phase,
};

String shortDuelAddress(String address) => address.length > 14
    ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
    : address;

/// `1,234.50000000 WRF` from a digit string of base units (1 WRF = 10^8), or
/// null for anything else: an unreadable amount is never shown as a number.
String? formatWrfBaseUnits(String? raw) {
  if (raw == null || !RegExp(r'^\d{1,39}$').hasMatch(raw)) return null;
  final units = BigInt.parse(raw);
  final perCoin = BigInt.from(100000000);
  final whole = (units ~/ perCoin).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final frac = (units % perCoin).toString().padLeft(8, '0');
  return '$whole.$frac WRF';
}

/// Whole UTC hours from 7 hours ahead, the earliest the server accepts (the
/// lock is 6 hours before the target), for the next 24 hours.
List<DateTime> duelTargetHourOptions(DateTime now) {
  const hourMs = 3600000;
  final earliest = now.toUtc().millisecondsSinceEpoch + 7 * hourMs;
  final first = (earliest + hourMs - 1) ~/ hourMs * hourMs;
  return List<DateTime>.generate(
    24,
    (i) => DateTime.fromMillisecondsSinceEpoch(first + i * hourMs, isUtc: true),
    growable: false,
  );
}

class DuelEntry {
  const DuelEntry({
    required this.address,
    this.commitId,
    this.recordVerified = false,
    this.temperatureC,
    this.chainReward,
    this.chainRewardFinalized = false,
    this.invalidReason,
  });

  final String address;
  final String? commitId;
  final bool recordVerified;

  /// Shown only once the record is verified, which needs the on-chain reveal.
  final double? temperatureC;

  /// Base units, as a digit string; null until the chain has decided.
  final String? chainReward;
  final bool chainRewardFinalized;
  final String? invalidReason;

  factory DuelEntry.fromJson(Map<String, dynamic> json) {
    final address = json['address'];
    if (address is! String) throw const FormatException('Entry has no address');
    final forecast = json['forecast'];
    final temperature = forecast is Map ? forecast['temperature_c'] : null;
    return DuelEntry(
      address: address.toLowerCase(),
      commitId: json['commitId'] as String?,
      recordVerified: json['recordVerified'] == true,
      temperatureC: temperature is num ? temperature.toDouble() : null,
      chainReward: json['chainReward']?.toString(),
      chainRewardFinalized: json['chainRewardFinalized'] == true,
      invalidReason: json['invalidReason'] as String?,
    );
  }
}

class DuelOutcome {
  const DuelOutcome({required this.result, this.winner, this.note});

  /// `creator`, `opponent`, `draw` or `void`, as the server names it.
  final String result;
  final String? winner;
  final String? note;

  String get label => switch (result) {
    'draw' => 'Draw',
    'void' => 'Void',
    _ => 'Decided',
  };
}

class Duel {
  const Duel({
    required this.id,
    required this.stationAlias,
    required this.phase,
    this.targetAt,
    this.lockAt,
    this.creator,
    this.opponent,
    this.invitedOpponent,
    this.outcome,
  });

  final String id;
  final String stationAlias;
  final String phase;
  final DateTime? targetAt;
  final DateTime? lockAt;
  final DuelEntry? creator;
  final DuelEntry? opponent;
  final String? invitedOpponent;
  final DuelOutcome? outcome;

  factory Duel.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final alias = json['stationAlias'];
    final phase = json['phase'];
    if (id is! String || alias is! String || phase is! String) {
      throw const FormatException('Duel is missing its id, station or phase');
    }
    DuelEntry? entry(Object? raw) =>
        raw is Map ? DuelEntry.fromJson(Map<String, dynamic>.from(raw)) : null;
    final outcome = json['outcome'];
    return Duel(
      id: id,
      stationAlias: alias,
      phase: phase,
      targetAt: DateTime.tryParse(json['targetAt']?.toString() ?? ''),
      lockAt: DateTime.tryParse(json['lockAt']?.toString() ?? ''),
      creator: entry(json['creator']),
      opponent: entry(json['opponent']),
      invitedOpponent: (json['invitedOpponent'] as String?)?.toLowerCase(),
      outcome: outcome is Map
          ? DuelOutcome(
              result: outcome['result']?.toString() ?? '',
              winner: (outcome['winner'] as String?)?.toLowerCase(),
              note: outcome['note'] as String?,
            )
          : null,
    );
  }

  /// The body of `GET /duels/:id` and of every write: `{duel: {...}}`.
  static Duel fromEnvelope(Object? payload) {
    final duel = payload is Map ? payload['duel'] : null;
    if (duel is! Map) throw const FormatException('Answer has no duel');
    return Duel.fromJson(Map<String, dynamic>.from(duel));
  }

  bool isPlayer(String? you) =>
      you != null && (creator?.address == you || opponent?.address == you);

  DuelEntry? mine(String? you) {
    if (!isPlayer(you)) return null;
    return creator?.address == you ? creator : opponent;
  }

  /// A signed-in wallet that is not playing can take an open seat, unless the
  /// duel names another wallet.
  bool canAccept(String? you) =>
      you != null &&
      !isPlayer(you) &&
      phase == 'open' &&
      (invitedOpponent == null || invitedOpponent == you);

  /// A player links one forecast, before the lock.
  bool canLink(String? you) =>
      isPlayer(you) &&
      mine(you)?.commitId == null &&
      (phase == 'open' || phase == 'committing');

  /// Anyone can hand in a linked forecast's record: it proves itself.
  bool get needsRecords =>
      (phase == 'judging' || phase == 'waiting_for_target') &&
      [creator, opponent].any(
        (entry) => entry?.commitId != null && entry?.recordVerified == false,
      );
}

class DuelBoard {
  const DuelBoard({
    this.open = const <Duel>[],
    this.live = const <Duel>[],
    this.finished = const <Duel>[],
  });

  final List<Duel> open;
  final List<Duel> live;
  final List<Duel> finished;

  factory DuelBoard.fromJson(Object? payload) {
    if (payload is! Map) throw const FormatException('Board is not an object');
    List<Duel> list(String key) {
      final raw = payload[key];
      if (raw is! List) throw FormatException('Board has no $key list');
      return raw
          .whereType<Map>()
          .map((item) => Duel.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    }

    return DuelBoard(
      open: list('open'),
      live: list('live'),
      finished: list('finished'),
    );
  }
}

/// `POST /duels` body.
class OpenDuelInput {
  const OpenDuelInput({
    required this.stationAlias,
    required this.targetAt,
    this.opponent = '',
  });

  final String stationAlias;
  final DateTime targetAt;
  final String opponent;

  Map<String, dynamic> toJson() {
    final other = opponent.trim();
    return {
      'stationAlias': stationAlias.trim().toLowerCase(),
      'targetAt': targetAt.toUtc().toIso8601String(),
      if (other.isNotEmpty) 'opponent': other,
    };
  }
}

/// `POST /duels/:id/record` body, from the forecast kit's `commit.json` and
/// `data.json`. The server hashes these against the linked commit id.
class DuelRecordInput {
  const DuelRecordInput({
    required this.commitId,
    required this.nonce,
    required this.timestamp,
    required this.data,
  });

  final String commitId;
  final Object? nonce;
  final Object? timestamp;
  final String data;

  /// Throws [FormatException] when `commit.json` is not a JSON object. The
  /// data keeps its bytes apart from line endings and outer whitespace, which
  /// the hash does not cover on the web page's hand-in either.
  factory DuelRecordInput.parse(String commitText, String dataText) {
    final Object? commit;
    try {
      commit = jsonDecode(commitText);
    } on FormatException {
      throw const FormatException('commit.json is not valid JSON.');
    }
    if (commit is! Map) {
      throw const FormatException('commit.json is not valid JSON.');
    }
    return DuelRecordInput(
      commitId: (commit['commit_id']?.toString() ?? '').toLowerCase(),
      nonce: commit['nonce'],
      timestamp: commit['timestamp'],
      data: dataText.replaceAll('\r\n', '\n').trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'commitId': commitId,
    'nonce': nonce,
    'timestamp': timestamp,
    'data': data,
  };
}
