import 'package:cryptography/cryptography.dart';

import '../../../../services/crypto/station_signing.dart';
import '../models/station_owner_models.dart';
import 'station_owner_api.dart';
import 'station_owner_exchange.dart';

// Transfer flow (spec rev e14b961, PROVISIONAL until core4 #3433 merges):
// sender signs a body fixed at ledger nonce + tip+5000; the new owner verifies
// EVERY field against its own wallet and the live ledger, countersigns the
// SAME body, and submits. A 201 only means "accepted"; the change is real
// when the ledger shows it.

/// Client rule from the spec: expiry = tip + 5000 (window is tip..tip+10000).
const int ownerTxExpiryBlocks = 5000;
const int ownerTxMaxValidityBlocks = 10000;

/// Opens the biometric-gated signing session; null when the user declined.
typedef StationSessionOpener = Future<StationSigningSession?> Function();

class StationOwnerCancelled implements Exception {
  const StationOwnerCancelled();
}

/// The ledger (or a gate) forbids the action; nothing was signed.
class StationOwnerBlocked implements Exception {
  const StationOwnerBlocked(this.reason);
  final String reason;
  @override
  String toString() => 'StationOwnerBlocked: $reason';
}

enum OfferProblem {
  wrongChain('This request is for a different network.'),
  notForThisWallet('This request is not addressed to this wallet.'),
  senderKeyNotBound('The sender key does not match the sender address.'),
  badSignature('The sender signature is not valid. Do not accept.'),
  senderIsNotOwner('The sender is not the current owner of this station.'),
  nonceMismatch('The station changed since this request was made.'),
  expired('This request has expired. Ask the sender for a new one.'),
  validityTooLong('This request has an invalid expiry.'),
  stationFrozen('This station is frozen and cannot be transferred.'),
  featureNotActive(
    'Station ownership changes are not active on the network yet.',
  ),
  recoveryAlreadyPending('A recovery is already pending for this station.'),
  malformed('This is not a valid transfer request.');

  const OfferProblem(this.message);
  final String message;
}

class OfferRejected implements Exception {
  const OfferRejected(this.problem);
  final OfferProblem problem;
  @override
  String toString() => 'OfferRejected(${problem.name})';
}

enum TransferStatus { pendingConfirmation, confirmed, unknown }

class TransferStarted {
  const TransferStarted({required this.offer, required this.ledger});
  final TransferOffer offer;
  final OwnerLedger ledger;
}

class TransferSubmission {
  const TransferSubmission({
    required this.stationId,
    required this.toOwnerAddress,
    required this.baselineNonce,
    required this.receipt,
  });
  final String stationId;
  final String toOwnerAddress;
  final int baselineNonce;
  final OwnerSubmitReceipt receipt;
}

List<int> _unhex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

class OwnerActionSubmission {
  const OwnerActionSubmission({
    required this.stationId,
    required this.action,
    required this.baselineNonce,
    required this.receipt,
  });
  final String stationId;
  final StationOwnerAction action;
  final int baselineNonce;
  final OwnerSubmitReceipt receipt;
}

class RecoveryCancelSubmission {
  const RecoveryCancelSubmission({
    required this.stationId,
    required this.baselineNonce,
    required this.receipt,
  });
  final String stationId;
  final int baselineNonce;
  final OwnerSubmitReceipt receipt;
}

class RecoveryExecuteSubmission {
  const RecoveryExecuteSubmission({
    required this.stationId,
    required this.toOwnerCommitment,
    required this.baselineNonce,
    required this.receipt,
  });
  final String stationId;

  /// The claimant's commitment (from the ledger's pending recovery);
  /// completion means the registered owner's commitment equals it.
  final String toOwnerCommitment;
  final int baselineNonce;
  final OwnerSubmitReceipt receipt;
}

/// Block time estimate from the 34,000-block / ~14-day notice window.
const double _approxSecondsPerBlock = 14 * 24 * 3600 / 34000;

/// Human estimate for a number of blocks. Callers label it approximate.
String approxRecoveryWait({required int blocksRemaining}) {
  if (blocksRemaining <= 0) return 'any moment now';
  final hours = blocksRemaining * _approxSecondsPerBlock / 3600;
  if (hours < 48) {
    final h = hours.round().clamp(1, 47);
    return 'about $h ${h == 1 ? 'hour' : 'hours'}';
  }
  return 'about ${(hours / 24).round()} days';
}

/// A recovery body that was fully checked against this wallet and the live
/// ledger. Countersigning returns text for the operator; nothing is sent.
class RecoveryAcceptFlow {
  RecoveryAcceptFlow({
    required this.request,
    required this.ledger,
    required this._onCountersign,
    required this._onClose,
  });

  final RecoveryRequest request;
  final OwnerLedger ledger;
  final Future<String> Function() _onCountersign;
  final void Function() _onClose;

  Future<String> countersign() => _onCountersign();
  void close() => _onClose();
}

class StationOwnerService {
  StationOwnerService({required this.api, required this.openSession});

  final StationOwnerApi api;
  final StationSessionOpener openSession;

  Future<StationSigningSession> _open() async {
    final s = await openSession();
    if (s == null) throw const StationOwnerCancelled();
    return s;
  }

  /// Signs and submits one owner action for this wallet's own station.
  /// Refused BEFORE any signature when the action has no core4 golden yet,
  /// the feature is inactive, this wallet is not the owner, or the ledger
  /// forbids the step. A returned submission only means "accepted".
  Future<OwnerActionSubmission> performOwnerAction(
    StationOwnerAction action,
  ) async {
    if (!action.shippable) {
      throw StationOwnerBlocked(
        '${action.wireName} is not available in this app version yet.',
      );
    }
    final session = await _open();
    try {
      final ledger = await api.readLedger(session.stationId);
      if (!ledger.actionsActive) {
        throw const StationOwnerBlocked(
          'Station owner actions are not active on the network yet.',
        );
      }
      if (!ledger.ownerIs(session.stationId, session.ownerAddress)) {
        throw const StationOwnerBlocked(
          'This wallet is not the owner of the station.',
        );
      }
      switch (action) {
        case StationOwnerAction.reportStolen:
          if (ledger.frozen) {
            throw const StationOwnerBlocked('The station is already frozen.');
          }
        case StationOwnerAction.unfreeze:
          if (!ledger.frozen) {
            throw const StationOwnerBlocked('The station is not frozen.');
          }
        case StationOwnerAction.deactivate:
          if (ledger.frozen || ledger.ownerDeactivated) {
            throw const StationOwnerBlocked(
              'The station is frozen or already deactivated.',
            );
          }
        case StationOwnerAction.reactivate:
          if (ledger.frozen || !ledger.ownerDeactivated) {
            throw const StationOwnerBlocked(
              'The station is frozen or not deactivated.',
            );
          }
      }
      final expires = ledger.observedAtHeight + ownerTxExpiryBlocks;
      final signed = await session.signOwnerAction(
        action: action,
        actionNonce: ledger.ownerNonce,
        expiresAtHeight: expires,
      );
      final receipt = await api.submit(
        SignedOwnerPayload(
          stationId: session.stationId,
          kind: 'owner_action',
          payload: ownerActionPayloadJson(
            stationId: session.stationId,
            ownerAddress: session.ownerAddress,
            ownerPubkey: signed.publicKeyHex,
            action: action,
            actionNonce: ledger.ownerNonce,
            expiresAtHeight: expires,
            ownerSignature: signed.signatureHex,
          ),
        ),
      );
      return OwnerActionSubmission(
        stationId: session.stationId,
        action: action,
        baselineNonce: ledger.ownerNonce,
        receipt: receipt,
      );
    } finally {
      session.close();
    }
  }

  /// One ledger read: applied only when the nonce advanced AND the action's
  /// effect is visible; any read failure is [TransferStatus.unknown].
  Future<TransferStatus> checkActionApplied(OwnerActionSubmission s) async {
    try {
      final ledger = await api.readLedger(s.stationId);
      final effect = switch (s.action) {
        StationOwnerAction.reportStolen => ledger.frozen,
        StationOwnerAction.unfreeze => !ledger.frozen,
        StationOwnerAction.deactivate => ledger.ownerDeactivated,
        StationOwnerAction.reactivate => !ledger.ownerDeactivated,
      };
      return effect && ledger.ownerNonce > s.baselineNonce
          ? TransferStatus.confirmed
          : TransferStatus.pendingConfirmation;
    } on StationOwnerException {
      return TransferStatus.unknown;
    }
  }

  /// Current owner: cancels the pending recovery. Refused before any
  /// signature unless it can work (consent active, this wallet is the owner,
  /// a recovery is pending at the matching nonce, window still open).
  Future<RecoveryCancelSubmission> cancelRecovery() async {
    final session = await _open();
    try {
      final ledger = await api.readLedger(session.stationId);
      final pending = ledger.pendingRecovery;
      if (!ledger.consentActive) {
        throw const StationOwnerBlocked(
          'Station ownership changes are not active on the network yet.',
        );
      }
      if (!ledger.ownerIs(session.stationId, session.ownerAddress)) {
        throw const StationOwnerBlocked(
          'This wallet is not the owner of the station.',
        );
      }
      if (pending == null) {
        throw const StationOwnerBlocked(
          'There is no recovery pending for this station.',
        );
      }
      if (pending.recoveryNonce != ledger.ownerNonce) {
        throw const StationOwnerBlocked(
          'The station changed since this recovery was filed.',
        );
      }
      if (ledger.observedAtHeight + 1 >= pending.executableAtHeight) {
        throw const StationOwnerBlocked(
          'The window to cancel this recovery has closed.',
        );
      }
      final signed = await session.signRecoveryCancel(
        recoveryNonce: pending.recoveryNonce,
      );
      final receipt = await api.submit(
        SignedOwnerPayload(
          stationId: session.stationId,
          kind: 'recovery_cancel',
          payload: recoveryCancelPayloadJson(
            stationId: session.stationId,
            ownerAddress: session.ownerAddress,
            ownerPubkey: signed.publicKeyHex,
            recoveryNonce: pending.recoveryNonce,
            ownerSignature: signed.signatureHex,
          ),
        ),
      );
      return RecoveryCancelSubmission(
        stationId: session.stationId,
        baselineNonce: ledger.ownerNonce,
        receipt: receipt,
      );
    } finally {
      session.close();
    }
  }

  /// Cancelled only when the pending recovery is gone AND the nonce advanced.
  Future<TransferStatus> checkRecoveryCancelled(
    RecoveryCancelSubmission s,
  ) async {
    try {
      final ledger = await api.readLedger(s.stationId);
      return ledger.pendingRecovery == null &&
              ledger.ownerNonce > s.baselineNonce
          ? TransferStatus.confirmed
          : TransferStatus.pendingConfirmation;
    } on StationOwnerException {
      return TransferStatus.unknown;
    }
  }

  /// Claimant: verifies an operator's recovery body against this wallet and
  /// the live ledger. Nothing is signed or sent until [RecoveryAcceptFlow.countersign],
  /// and that never submits.
  Future<RecoveryAcceptFlow> beginRecoveryAccept(String text) async {
    final RecoveryRequest request;
    try {
      request = RecoveryRequest.decode(text);
    } on FormatException {
      throw const OfferRejected(OfferProblem.malformed);
    }
    final session = await _open();
    try {
      final b = request.body;
      final ledger = await api.readLedger(b.stationId);
      _verifyRecovery(b, session, ledger);
      return RecoveryAcceptFlow(
        request: request,
        ledger: ledger,
        onCountersign: () async {
          // Re-check against a ledger read IMMEDIATELY before signing.
          _verifyRecovery(b, session, await api.readLedger(b.stationId));
          final sig = await session.countersignRecoveryAccept(b);
          return RecoveryAcceptText(
            body: b,
            toOwnerSignature: sig.signatureHex,
          ).encode();
        },
        onClose: session.close,
      );
    } catch (_) {
      session.close();
      rethrow;
    }
  }

  void _verifyRecovery(
    StationRecoveryBody b,
    StationSigningSession session,
    OwnerLedger ledger,
  ) {
    if (b.chainId != session.chainId || b.networkId != session.networkId) {
      throw const OfferRejected(OfferProblem.wrongChain);
    }
    if (!sameStationOwner(b.toOwnerAddress, session.ownerAddress) ||
        b.toOwnerPubkey != session.publicKeyHex ||
        sameStationOwner(b.fromOwnerAddress, b.toOwnerAddress)) {
      throw const OfferRejected(OfferProblem.notForThisWallet);
    }
    if (!ledger.consentActive) {
      throw const OfferRejected(OfferProblem.featureNotActive);
    }
    if (!ledger.ownerIs(b.stationId, b.fromOwnerAddress)) {
      throw const OfferRejected(OfferProblem.senderIsNotOwner);
    }
    if (ledger.pendingRecovery != null) {
      throw const OfferRejected(OfferProblem.recoveryAlreadyPending);
    }
    if (ledger.ownerNonce != b.recoveryNonce) {
      throw const OfferRejected(OfferProblem.nonceMismatch);
    }
  }

  /// Anyone: completes a recovery once its window has passed. Unsigned.
  Future<RecoveryExecuteSubmission> executeRecovery(String stationId) async {
    final ledger = await api.readLedger(stationId);
    final pending = ledger.pendingRecovery;
    if (pending == null) {
      throw const StationOwnerBlocked(
        'There is no recovery pending for this station.',
      );
    }
    if (!ledger.consentActive) {
      throw const StationOwnerBlocked(
        'Station ownership changes are not active on the network yet.',
      );
    }
    final remaining =
        pending.executableAtHeight - (ledger.observedAtHeight + 1);
    if (remaining > 0) {
      throw StationOwnerBlocked(
        'This recovery can be completed in ${approxRecoveryWait(blocksRemaining: remaining)} (estimate).',
      );
    }
    final receipt = await api.submit(
      SignedOwnerPayload(
        stationId: stationId,
        kind: 'recovery_execute',
        payload: recoveryExecutePayloadJson(
          stationId: stationId,
          recoveryNonce: pending.recoveryNonce,
        ),
      ),
    );
    return RecoveryExecuteSubmission(
      stationId: stationId,
      toOwnerCommitment: pending.toOwnerCommitment,
      baselineNonce: ledger.ownerNonce,
      receipt: receipt,
    );
  }

  /// Completed only when the registered owner's commitment IS the claimant's
  /// commitment recorded at submit, the nonce advanced and no recovery is
  /// pending. Commitments are compared; the short display addresses never are.
  Future<TransferStatus> checkRecoveryExecuted(
    RecoveryExecuteSubmission s,
  ) async {
    try {
      final ledger = await api.readLedger(s.stationId);
      return ledger.ownerCommitment == s.toOwnerCommitment &&
              ledger.pendingRecovery == null &&
              ledger.ownerNonce > s.baselineNonce
          ? TransferStatus.confirmed
          : TransferStatus.pendingConfirmation;
    } on StationOwnerException {
      return TransferStatus.unknown;
    }
  }

  /// Public receive details of this wallet (address and public key only).
  Future<ReceiveCode> myReceiveCode() async {
    final session = await _open();
    try {
      return ReceiveCode(
        address: session.ownerAddress,
        pubkey: session.publicKeyHex,
      );
    } finally {
      session.close();
    }
  }

  /// Sender: signs an offer for [to]. Reads the ledger first, so the nonce is
  /// never stale and a doomed transfer is refused before any signature.
  Future<TransferStarted> startTransfer(ReceiveCode to) async {
    final session = await _open();
    try {
      final ledger = await api.readLedger(session.stationId);
      if (!ledger.consentActive) {
        throw const StationOwnerBlocked(
          'Station ownership changes are not active yet.',
        );
      }
      if (!ledger.ownerIs(session.stationId, session.ownerAddress)) {
        throw const StationOwnerBlocked(
          'This wallet is not the owner of the station.',
        );
      }
      if (ledger.frozen) {
        throw const StationOwnerBlocked(
          'The station is frozen. Unfreeze it before transferring.',
        );
      }
      final signed = await session.signTransferAsSender(
        toOwnerAddress: to.address,
        toOwnerPubkey: to.pubkey,
        transferNonce: ledger.ownerNonce,
        expiresAtHeight: ledger.observedAtHeight + ownerTxExpiryBlocks,
      );
      return TransferStarted(
        offer: TransferOffer.fromSigned(signed),
        ledger: ledger,
      );
    } finally {
      session.close();
    }
  }

  /// New owner: decodes and verifies an offer. Nothing is signed or sent.
  /// The returned flow keeps the session open until [AcceptFlow.close].
  Future<AcceptFlow> beginAccept(String text) async {
    final TransferOffer offer;
    try {
      offer = TransferOffer.decode(text);
    } on FormatException {
      throw const OfferRejected(OfferProblem.malformed);
    }
    final session = await _open();
    try {
      final ledger = await api.readLedger(offer.body.stationId);
      await _verify(offer, session, ledger);
      return AcceptFlow(
        offer: offer,
        ledger: ledger,
        onAccept: () async {
          // The review screen may have been open for minutes: verify against
          // a ledger read IMMEDIATELY before signing.
          await _verify(
            offer,
            session,
            await api.readLedger(offer.body.stationId),
          );
          final sig = await session.countersignTransferAccept(offer.body);
          final receipt = await api.submit(
            SignedOwnerPayload(
              stationId: offer.body.stationId,
              kind: 'transfer',
              payload: transferPayloadJson(
                offer,
                toOwnerSignature: sig.signatureHex,
              ),
            ),
          );
          return TransferSubmission(
            stationId: offer.body.stationId,
            toOwnerAddress: offer.body.toOwnerAddress,
            baselineNonce: offer.body.transferNonce,
            receipt: receipt,
          );
        },
        onClose: session.close,
      );
    } catch (_) {
      session.close();
      rethrow;
    }
  }

  Future<void> _verify(
    TransferOffer offer,
    StationSigningSession session,
    OwnerLedger ledger,
  ) async {
    final b = offer.body;
    if (b.chainId != session.chainId || b.networkId != session.networkId) {
      throw const OfferRejected(OfferProblem.wrongChain);
    }
    if (!sameStationOwner(b.toOwnerAddress, session.ownerAddress) ||
        b.toOwnerPubkey != session.publicKeyHex) {
      throw const OfferRejected(OfferProblem.notForThisWallet);
    }
    if (!sameStationOwner(
      b.fromOwnerAddress,
      addressOfEd25519PublicKeyHex(offer.fromOwnerPubkey),
    )) {
      throw const OfferRejected(OfferProblem.senderKeyNotBound);
    }
    if (sameStationOwner(b.fromOwnerAddress, b.toOwnerAddress)) {
      throw const OfferRejected(OfferProblem.notForThisWallet);
    }
    final ok = await Ed25519().verify(
      stationOwnerTransferMessage(b),
      signature: Signature(
        _unhex(offer.fromOwnerSignature),
        publicKey: SimplePublicKey(
          _unhex(offer.fromOwnerPubkey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!ok) throw const OfferRejected(OfferProblem.badSignature);

    if (!ledger.consentActive) {
      throw const OfferRejected(OfferProblem.featureNotActive);
    }
    if (!ledger.ownerIs(b.stationId, b.fromOwnerAddress)) {
      throw const OfferRejected(OfferProblem.senderIsNotOwner);
    }
    if (ledger.frozen) throw const OfferRejected(OfferProblem.stationFrozen);
    if (ledger.ownerNonce != b.transferNonce) {
      throw const OfferRejected(OfferProblem.nonceMismatch);
    }
    final next = ledger.observedAtHeight + 1;
    if (next > b.expiresAtHeight) {
      throw const OfferRejected(OfferProblem.expired);
    }
    if (b.expiresAtHeight > next + ownerTxMaxValidityBlocks) {
      throw const OfferRejected(OfferProblem.validityTooLong);
    }
  }

  /// One ledger read to see whether the transfer took effect. Confirmed only
  /// when the owner is the new owner AND the nonce advanced; any read failure
  /// is [TransferStatus.unknown], never success.
  Future<TransferStatus> checkTransferApplied(TransferSubmission s) =>
      checkApplied(
        stationId: s.stationId,
        toOwnerAddress: s.toOwnerAddress,
        baselineNonce: s.baselineNonce,
      );

  Future<TransferStatus> checkApplied({
    required String stationId,
    required String toOwnerAddress,
    required int baselineNonce,
  }) async {
    try {
      final ledger = await api.readLedger(stationId);
      final moved = ledger.ownerIs(stationId, toOwnerAddress);
      return moved && ledger.ownerNonce > baselineNonce
          ? TransferStatus.confirmed
          : TransferStatus.pendingConfirmation;
    } on StationOwnerException {
      return TransferStatus.unknown;
    }
  }
}

/// A verified offer awaiting the new owner's confirmation. Holds the signing
/// session until [close].
class AcceptFlow {
  AcceptFlow({
    required this.offer,
    required this.ledger,
    required this._onAccept,
    required this._onClose,
  });

  final TransferOffer offer;
  final OwnerLedger ledger;
  final Future<TransferSubmission> Function() _onAccept;
  final void Function() _onClose;

  /// Countersigns the same body and submits both signatures. The offer was
  /// fully verified by [StationOwnerService.beginAccept] before this exists.
  Future<TransferSubmission> accept() => _onAccept();

  void close() => _onClose();
}
