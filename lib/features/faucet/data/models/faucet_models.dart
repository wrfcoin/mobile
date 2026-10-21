/// Models for the testnet faucet onboarding flow.
///
/// Mirrors the backend contract in
/// `backend/server/routes/onboarding-routes.ts`:
///   - `POST /onboarding/faucet/challenge` → `{ challengeId, question }`
///   - `POST /onboarding/faucet/claim`     → `{ txHash, amount, balance }`
///                                          | `{ error: { code, message } }`
library;

/// A math-captcha challenge issued by the faucet.
///
/// The backend stores the answer server-side keyed by [challengeId] with a
/// 5-minute TTL; the client only ever sees the human-readable [question].
class FaucetChallenge {
  /// Opaque id echoed back on claim so the backend can match the answer.
  final String challengeId;

  /// Human-readable prompt, e.g. `"What is 7 + 12?"`.
  final String question;

  const FaucetChallenge({required this.challengeId, required this.question});

  factory FaucetChallenge.fromJson(Map<String, dynamic> json) {
    final id = json['challengeId']?.toString() ?? '';
    final q = json['question']?.toString() ?? '';
    if (id.isEmpty || q.isEmpty) {
      throw StateError(
        'Faucet challenge response was missing required fields.',
      );
    }
    return FaucetChallenge(challengeId: id, question: q);
  }
}

/// A successful faucet dispense result.
class FaucetClaimResult {
  /// On-chain transaction hash of the dispense.
  final String txHash;

  /// Amount dispensed, as returned by the backend (string base units / WRF).
  final String amount;

  /// Live wallet balance after the dispense, if the backend reported one.
  final String? balance;

  const FaucetClaimResult({
    required this.txHash,
    required this.amount,
    this.balance,
  });

  factory FaucetClaimResult.fromJson(Map<String, dynamic> json) {
    final txHash = json['txHash']?.toString() ?? '';
    if (txHash.isEmpty) {
      throw StateError('Faucet claim response was missing a transaction hash.');
    }
    return FaucetClaimResult(
      txHash: txHash,
      amount: json['amount']?.toString() ?? '0',
      balance: json['balance']?.toString(),
    );
  }
}
