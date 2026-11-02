import 'dart:convert';

/// Where this device's latest send stands. "Included" is the only state that
/// means the chain has this exact send; see [PendingSend].
enum PendingSendPhase {
  /// Signed and being posted now. Read back after a restart as
  /// [outcomeUnknown], because the post's answer was lost with the app.
  sending,

  /// The backend answered 202: accepted, not settled.
  submitted,

  /// The post got no definite answer, so it may or may not have gone through.
  outcomeUnknown,

  /// The chain's nonce moved past this send and this exact transaction is in
  /// the wallet's chain history.
  included,

  /// The chain's nonce moved past this send, but this exact transaction could
  /// not be matched: some transaction with that number has been applied.
  nonceUsedUnmatched;

  /// Still waiting on the chain, so the account's next nonce is in doubt.
  bool get awaitingChain => switch (this) {
    sending || submitted || outcomeUnknown => true,
    included || nonceUsedUnmatched => false,
  };
}

/// The status of one send, kept so the wallet can say what happened to it after
/// the app restarts. There is one at most, and it is replaced by the next send.
/// It is not a history: wallet history only ever comes from the chain.
class PendingSend {
  const PendingSend({
    required this.from,
    required this.to,
    required this.amountBaseUnits,
    required this.nonce,
    required this.submittedAt,
    required this.phase,
    this.hash,
    this.blockHeight,
  });

  final String from;
  final String to;
  final String amountBaseUnits;

  /// The nonce this send was signed with, a decimal string.
  final String nonce;
  final DateTime submittedAt;
  final PendingSendPhase phase;
  final String? hash;
  final int? blockHeight;

  PendingSend copyWith({
    PendingSendPhase? phase,
    String? hash,
    int? blockHeight,
  }) => PendingSend(
    from: from,
    to: to,
    amountBaseUnits: amountBaseUnits,
    nonce: nonce,
    submittedAt: submittedAt,
    phase: phase ?? this.phase,
    hash: hash ?? this.hash,
    blockHeight: blockHeight ?? this.blockHeight,
  );

  String encode() => jsonEncode({
    'from': from,
    'to': to,
    'amountBaseUnits': amountBaseUnits,
    'nonce': nonce,
    'submittedAt': submittedAt.toUtc().toIso8601String(),
    'phase': phase.name,
    'hash': hash,
    'blockHeight': blockHeight,
  });

  /// Null for anything unreadable, which must never block Send.
  static PendingSend? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final nonce = json['nonce'] as String;
      if (BigInt.tryParse(nonce) == null) return null;
      final phase = PendingSendPhase.values.byName(json['phase'] as String);
      return PendingSend(
        from: json['from'] as String,
        to: json['to'] as String,
        amountBaseUnits: json['amountBaseUnits'] as String,
        nonce: nonce,
        submittedAt: DateTime.parse(json['submittedAt'] as String).toUtc(),
        phase: phase == PendingSendPhase.sending
            ? PendingSendPhase.outcomeUnknown
            : phase,
        hash: json['hash'] as String?,
        blockHeight: json['blockHeight'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}
