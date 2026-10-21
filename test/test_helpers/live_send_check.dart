// Logic of the owner-run live send check (scripts/live_testnet_send_check.sh),
// kept free of any network or clock so the STOP paths are unit tested with
// fakes (test/integration/live_send_check_logic_test.dart).
//
// Rules this file enforces for the live run:
//  * the faucet account must exist and hold spendable balance BEFORE any claim
//    or send (a faucet that is not funded yet, before E0f/H_F, would stall the
//    run and look like a send failure);
//  * one claim attempt, one send (never retried), and an inclusion poll bounded
//    to [maxInclusionPolls] reads;
//  * every printed line passes [publicLine], which refuses to print a known
//    secret (mnemonic, key, JWT, token).
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';

/// Deployed signing domain of the testnet (infra docker-compose
/// WRFCOIN_CHAIN_ID "777", WRFCOIN_NETWORK_ID testnet). Explicit on purpose:
/// the live check never reads a build-time override.
const String liveChainId = '777';
const String liveNetworkId = 'testnet';

/// Fee reserve (0.01 WRF) the sender must hold on top of the amount; override with
/// WRFCOIN_LIVE_FEE_BASE_UNITS.
const String defaultFeeReserveBaseUnits = '1000000';

/// The most nonce reads the inclusion poll makes after the send.
const int maxInclusionPolls = 30;

/// A precondition failed: print [message] and stop. Nothing is retried.
class LiveSendStop implements Exception {
  const LiveSendStop(this.message);
  final String message;
  @override
  String toString() => 'STOP $message';
}

/// The send was attempted but no definitive answer came back (timeout, connection error, 5xx):
/// the transfer may or may not have been admitted. The run reports this and stops; it never re-sends.
class LiveSendUnknownOutcome implements Exception {
  const LiveSendUnknownOutcome();
}

const String unknownOutcomeMessage =
    'unknown outcome: the send may have been admitted; check the wallet nonce (and the recipient '
    'at the node) before retrying, and do not run send again until you have';

/// A Dio with NO interceptors (so no retry) and a bearer set once. Every call is exactly one wire
/// request. Used for the owner's nonce reads and the single send; ApiClient's own Dio retries
/// timeouts and 5xx for every method and must not carry a live transfer.
Dio oneShotDio({
  required String baseUrl,
  String? bearer,
  HttpClientAdapter? adapter,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (bearer != null) 'Authorization': 'Bearer $bearer',
      },
    ),
  );
  if (adapter != null) dio.httpClientAdapter = adapter;
  return dio;
}

/// True when [e] leaves the outcome of a POST unknown (no response, or a server error).
bool isUnknownOutcome(DioException e) {
  final status = e.response?.statusCode;
  return status == null || status >= 500;
}

/// Exactly ONE signed POST through [wallets] (which must sit on a [oneShotDio]). A timeout,
/// dropped connection or 5xx means the transfer may have been admitted: it becomes
/// [LiveSendUnknownOutcome] and is never re-sent. A definite 4xx propagates as the DioException.
Future<String> sendOnce({
  required WalletRemoteDataSource wallets,
  required String from,
  required String to,
  required String amountBaseUnits,
  required Ed25519TransferSigner signer,
}) async {
  try {
    final result = await wallets.sendTransaction(
      from: from,
      to: to,
      amountBaseUnits: amountBaseUnits,
      signer: signer,
    );
    return '${result['hash']}';
  } on DioException catch (e) {
    if (e.requestOptions.method.toUpperCase() == 'POST' && isUnknownOutcome(e)) {
      throw const LiveSendUnknownOutcome();
    }
    rethrow;
  }
}

const String faucetNotFundedMessage =
    'faucet not funded yet: run after E0f/H_F';

/// Null when the faucet account read shows spendable balance; otherwise the
/// plain STOP message. [status] is the node's HTTP status, [body] the decoded
/// JSON envelope (`{ok, data:{spendable_balance,...}}`).
String? faucetStopReason(int? status, Object? body) {
  if (status == null) {
    return 'cannot read the faucet account (no answer from the node); '
        'not claiming or sending';
  }
  if (status == 404) return '$faucetNotFundedMessage (faucet account not on chain)';
  if (status != 200) {
    return 'cannot read the faucet account (node answered HTTP $status); '
        'not claiming or sending';
  }
  final data = body is Map ? body['data'] : null;
  // ONLY spendable_balance counts: a total `balance` (which can be locked or staked) must never
  // stand in for it. Absent, null, non-numeric and 0 all STOP.
  final raw = data is Map ? data['spendable_balance'] : null;
  if (raw == null || !RegExp(r'^\d+$').hasMatch('$raw')) {
    return 'cannot read the faucet spendable_balance; not claiming or sending';
  }
  if (BigInt.parse('$raw') == BigInt.zero) {
    return '$faucetNotFundedMessage (spendable_balance is 0)';
  }
  return null;
}

/// Null when the sender's node account read shows spendable balance of at least
/// amount + [feeReserveBaseUnits]; otherwise the plain STOP message. The fee is only reported by
/// the backend after submit, so it is a reserve the owner can override, not a quote.
String? senderStopReason(
  int? status,
  Object? body, {
  required String amountBaseUnits,
  required String feeReserveBaseUnits,
}) {
  if (status == null) {
    return 'cannot read the sender balance (no answer from the node); not sending';
  }
  if (status == 404) return 'sender account not on chain; not sending';
  if (status != 200) {
    return 'cannot read the sender balance (node answered HTTP $status); not sending';
  }
  final data = body is Map ? body['data'] : null;
  final raw = data is Map ? data['spendable_balance'] : null;
  if (raw == null || !RegExp(r'^\d+$').hasMatch('$raw')) {
    return 'cannot read the sender spendable_balance; not sending';
  }
  final need =
      BigInt.parse(amountBaseUnits) + BigInt.parse(feeReserveBaseUnits);
  final have = BigInt.parse('$raw');
  if (have < need) {
    return 'sender spendable balance $have is below amount + fee $need base units; not sending';
  }
  return null;
}

final RegExp _chainAddress = RegExp(r'^0x[0-9a-f]{40}$');

/// The send's recipient. An explicit [recipient] is required; only an explicit [selfTest] opt-in
/// may fall back to a [random] throwaway address. Always a lowercase 0x + 40 hex address, never
/// the [sender].
String resolveRecipient({
  required String recipient,
  required bool selfTest,
  required String Function() random,
  String? sender,
}) {
  var to = recipient.trim().toLowerCase();
  if (to.isEmpty) {
    if (!selfTest) {
      throw const LiveSendStop(
        'WRFCOIN_LIVE_RECIPIENT must be set (or WRFCOIN_LIVE_SELF_TEST_RECIPIENT=1 for a random '
        'throwaway recipient); not sending',
      );
    }
    to = random().toLowerCase();
  }
  if (!_chainAddress.hasMatch(to)) {
    throw const LiveSendStop(
      'recipient must be a 0x-prefixed 40-hex chain address; not sending',
    );
  }
  if (sender != null && to == sender.toLowerCase()) {
    throw const LiveSendStop('recipient is the sender itself; not sending');
  }
  return to;
}

/// [line] unchanged, or a [StateError] if it contains any of [secrets] (empty
/// and very short values are ignored). Defence in depth for what is printed.
String publicLine(String line, Iterable<String> secrets) {
  for (final secret in secrets) {
    if (secret.length >= 6 && line.contains(secret)) {
      throw StateError('refusing to print a line that contains a secret value');
    }
  }
  return line;
}

class InclusionResult {
  const InclusionResult({required this.settled, required this.polls, this.nonce});
  final bool settled;
  final int polls;
  final BigInt? nonce;
}

/// Reads the sender nonce until it differs from [before], at most [maxPolls]
/// times, waiting [wait] between reads. Never more reads than [maxPolls].
Future<InclusionResult> pollNonceAdvance({
  required Future<BigInt> Function() readNonce,
  required BigInt before,
  required Future<void> Function() wait,
  int maxPolls = maxInclusionPolls,
}) async {
  final bounded = maxPolls > maxInclusionPolls ? maxInclusionPolls : maxPolls;
  var polls = 0;
  while (polls < bounded) {
    await wait();
    polls += 1;
    final now = await readNonce();
    if (now != before) return InclusionResult(settled: true, polls: polls, nonce: now);
  }
  return InclusionResult(settled: false, polls: polls);
}

/// Ports the orchestration talks through (real ones in the live test, fakes in
/// the unit tests).
class LiveSendPorts {
  const LiveSendPorts({
    required this.readFaucet,
    required this.signIn,
    required this.readOwnNonce,
    required this.readOwnAccount,
    required this.send,
    required this.wait,
    required this.say,
  });

  /// (HTTP status, decoded body) of the node's faucet account read, or null status.
  final Future<(int?, Object?)> Function() readFaucet;

  /// Explicit wallet sign-in (the client never logs in on its own), true on success.
  /// Called only after the faucet precondition passed and before the first owner read.
  final Future<bool> Function() signIn;

  /// The wallet's chain nonce, or null while the account is not on chain.
  final Future<BigInt?> Function() readOwnNonce;

  /// (HTTP status, decoded body) of the node's read of the sender's own account.
  final Future<(int?, Object?)> Function() readOwnAccount;

  /// Signs and submits ONE transfer; returns its public tx id.
  final Future<String> Function(BigInt nonce) send;
  final Future<void> Function() wait;
  final void Function(String line) say;
}

class LiveSendCheck {
  LiveSendCheck(
    this.ports, {
    this.amountBaseUnits = '100000000',
    this.feeReserveBaseUnits = defaultFeeReserveBaseUnits,
  });
  final LiveSendPorts ports;
  final String amountBaseUnits;
  final String feeReserveBaseUnits;

  Future<void> _faucetPrecondition() async {
    final (status, body) = await ports.readFaucet();
    final reason = faucetStopReason(status, body);
    if (reason != null) throw LiveSendStop(reason);
    ports.say('faucet account funded (precondition ok)');
  }

  /// Faucet precondition, then one read of the wallet's own nonce. Prints
  /// `FUNDED=yes|no` for the script. Makes no transaction.
  Future<void> _authenticate() async {
    if (!await ports.signIn()) {
      throw const LiveSendStop('wallet sign-in failed; not reading the wallet, claiming or sending');
    }
    ports.say('wallet sign-in ok');
  }

  Future<bool> check() async {
    await _faucetPrecondition();
    await _authenticate();
    final nonce = await ports.readOwnNonce();
    ports.say(nonce == null ? 'wallet not on chain yet (unfunded)' : 'wallet on chain, nonce=$nonce');
    ports.say('FUNDED=${nonce == null ? 'no' : 'yes'}');
    return nonce != null;
  }

  /// Faucet precondition, wallet must already be funded, ONE send (never
  /// retried), then a poll bounded to [maxInclusionPolls] nonce reads.
  Future<InclusionResult> send() async {
    await _faucetPrecondition();
    await _authenticate();
    final nonce = await ports.readOwnNonce();
    if (nonce == null) {
      throw const LiveSendStop(
        'wallet not funded on chain yet: claim from the faucet, wait until it '
        'settles, then run send again',
      );
    }
    final (accStatus, accBody) = await ports.readOwnAccount();
    final low = senderStopReason(
      accStatus,
      accBody,
      amountBaseUnits: amountBaseUnits,
      feeReserveBaseUnits: feeReserveBaseUnits,
    );
    if (low != null) throw LiveSendStop(low);
    final String txId;
    try {
      txId = await ports.send(nonce); // exactly one attempt, never retried
    } on LiveSendUnknownOutcome {
      ports.say(unknownOutcomeMessage);
      throw const LiveSendStop(unknownOutcomeMessage);
    }
    ports.say('ACCEPTED tx=$txId nonce=$nonce');
    final InclusionResult result;
    try {
      result = await pollNonceAdvance(
        readNonce: () async => (await ports.readOwnNonce()) ?? nonce,
        before: nonce,
        wait: ports.wait,
      );
    } catch (_) {
      ports.say('lost the nonce read while waiting; tx=$txId is accepted, its inclusion is unknown; check the nonce before doing anything else');
      rethrow;
    }
    if (result.settled) {
      ports.say('SETTLED nonce $nonce -> ${result.nonce} tx=$txId');
    } else {
      ports.say('NOT SETTLED after ${result.polls} reads (nonce still $nonce); tx=$txId; '
          'check the producer, do not resend blindly (the same nonce is replay-guarded)');
    }
    return result;
  }
}
