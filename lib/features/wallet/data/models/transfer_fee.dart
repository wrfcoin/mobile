import '../../../../core/utils/wrf_units.dart';

/// What the phone knows about the network fee for a transfer.
enum TransferFeeState {
  /// The network stated the fee. It may be zero.
  known,

  /// The answer has no fee field. That is today's backend: core4 reports the
  /// fee on `/network/info`, and the relay does not pass it on yet.
  notReported,

  /// The read failed or its fee field can't be trusted. Send stops.
  unknown,
}

/// The network fee, read from the `transfer_fee` field of
/// `GET /wallet/<address>/nonce`, in the shape core4 uses on `/network/info`.
///
/// The client never declares a fee. As on the web, the signed body is
/// from|to|amount|nonce and the node declares and enforces the fee. This only
/// decides what the user is shown and how much balance a send must leave.
class TransferFeeQuote {
  const TransferFeeQuote._(this.state, this.baseUnits, this.scheduled);

  /// A fee in force now, or zero with [scheduled] when one starts later.
  factory TransferFeeQuote.known(BigInt baseUnits, {bool scheduled = false}) =>
      TransferFeeQuote._(TransferFeeState.known, baseUnits, scheduled);

  static const TransferFeeQuote notReported = TransferFeeQuote._(
    TransferFeeState.notReported,
    null,
    false,
  );

  static const TransferFeeQuote unknown = TransferFeeQuote._(
    TransferFeeState.unknown,
    null,
    false,
  );

  /// Reads the fee from a nonce answer. A missing field is [notReported]; a
  /// present field that doesn't match the contract is [unknown], never zero.
  factory TransferFeeQuote.fromNonceResponse(Map<String, dynamic> response) {
    if (!response.containsKey('transfer_fee')) return notReported;
    final fee = response['transfer_fee'];
    if (fee is! Map) return unknown;
    final active = fee['active'], scheduled = fee['scheduled'];
    final raw = fee['base_units'];
    if (active is! bool ||
        scheduled is! bool ||
        raw is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(raw)) {
      return unknown;
    }
    final units = BigInt.parse(raw);
    // An active fee of zero, or an inactive fee with a figure, contradicts
    // core4's contract, so neither is believed.
    if (active != (units > BigInt.zero)) return unknown;
    return TransferFeeQuote.known(units, scheduled: scheduled && !active);
  }

  final TransferFeeState state;
  final BigInt? baseUnits;

  /// No fee applies now, but the chain has one scheduled.
  final bool scheduled;

  /// What a send must keep back, or null when Send has to stop.
  BigInt? get reserveBaseUnits => switch (state) {
    TransferFeeState.known => baseUnits,
    TransferFeeState.notReported => BigInt.zero,
    TransferFeeState.unknown => null,
  };

  /// True when the figure comes from the network, not from its absence.
  bool get isStated => state == TransferFeeState.known;

  String get label => switch (state) {
    TransferFeeState.known when baseUnits! > BigInt.zero =>
      'Network fee: ${wrfBaseUnitsToDisplay(baseUnits.toString())} WRF (burned)',
    TransferFeeState.known =>
      scheduled
          ? 'Network fee: none yet (a fee is scheduled)'
          : 'Network fee: none',
    TransferFeeState.notReported => 'Network fee: none reported by the network',
    TransferFeeState.unknown => kNetworkFeeUnavailable,
  };
}

/// Shown when a fee can't be read; Send stays stopped until it can.
const String kNetworkFeeUnavailable = 'Network fee unavailable — try again';
