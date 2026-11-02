import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/feature_flags/build_flags.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/wrf_units.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/crypto/signed_transfer.dart';
import '../../data/models/address_book_entry.dart';
import '../../data/models/transfer_fee.dart';
import '../../data/models/wallet_model.dart';
import '../../domain/recipient_safety.dart';
import '../../data/repositories/wallet_repository_impl.dart';
import '../providers/transactions_provider.dart';
import '../providers/wallet_provider.dart';
import '../providers/wallet_security_provider.dart';

/// Launch gate for the shielded-send privacy tiers.
///
/// The Enhanced/Maximum tiers route through [WalletNotifier.sendPrivateTransaction],
/// which hits the backend's `/send-private` (stealth-address) path. That path
/// currently returns HTTP 501 — the real shielded pool requires a
/// consensus-disabled revival tracked in core4#2080 (mobile#216 is deferred to
/// that epic). Until core4#2080 lands, only Standard sends are exposed so users
/// can't select a tier that fails. Flip this to `true` to re-enable the tiers —
/// a one-line change once the backend supports private transfers.
const bool kEnhancedPrivacyTiersEnabled = false;

/// Launch gate for account-abstraction sponsored sends.
///
/// Re-enable with a one-line `true` change under wrfcoin/core4#2167 once the
/// sponsored user-operation contract is served end to end.
const bool kSponsoredSendEnabled = false;

@visibleForTesting
Future<bool> sponsoredSendEnabled(
  Future<bool> Function() readSocialWallet,
) async {
  if (!kSponsoredSendEnabled) return false;
  return readSocialWallet();
}

@visibleForTesting
Map<String, dynamic> buildSponsoredUserOperation({
  required String from,
  required String to,
  required String amount,
  String? memo,
}) {
  return {
    'sender': from,
    'to': to,
    'amount': amount,
    if (memo != null && memo.isNotEmpty) 'memo': memo,
    'callData': '0x',
  };
}

BigInt? _walletBalanceUnits(AsyncValue<WalletModel?> wallet) {
  // Do not use retained data during a refresh or after a failed read.
  if (wallet.isLoading || wallet.hasError) return null;
  final balance = wallet.value?.balance;
  if (balance == null || wrfBaseUnitsToDisplay(balance) == null) return null;
  return BigInt.parse(balance.trim());
}

const _balanceUnavailable = 'Balance unavailable — refresh and try again';

/// Reads the same provider as WalletScreen, including changes while open.
class SendConfirmationDialog extends ConsumerWidget {
  const SendConfirmationDialog({
    super.key,
    required this.to,
    required this.amountBaseUnits,
    this.fee = TransferFeeQuote.unknown,
    this.sponsored = false,
    this.contact,
  });

  final String to;
  final AddressBookEntry? contact;
  final String amountBaseUnits;
  final TransferFeeQuote fee;
  final bool sponsored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = _walletBalanceUnits(ref.watch(walletProvider));
    final amount = BigInt.parse(amountBaseUnits);
    final reserve = sponsored ? BigInt.zero : fee.reserveBaseUnits;
    final after = balance == null || reserve == null
        ? null
        : balance - amount - reserve;
    final canSend = after != null && after >= BigInt.zero;
    // With no figure from the network, the balance after is only an estimate.
    final approximate = !sponsored && !fee.isStated;
    final feeText = sponsored ? 'Network fee: Free transfer' : fee.label;
    final contactLine = switch (contact?.status) {
      null => 'Recipient not verified: confirm the full address above',
      AddressStatus.verifiedCurrent =>
        'Saved contact "${contact!.label}" (marked current)',
      _ =>
        'Saved contact "${contact!.label}": address not verified, '
            'confirm the full address above',
    };
    final lines = <String>[
      'To: $to',
      contactLine,
      'Amount: ${wrfBaseUnitsToDisplay(amountBaseUnits)} WRF',
      feeText,
      balance == null
          ? 'Current balance: unavailable'
          : 'Current balance: ${wrfBaseUnitsToDisplay(balance.toString())} WRF',
      if (after != null)
        'Balance after: ${approximate ? 'about ' : ''}'
            '${after.isNegative ? '-' : ''}'
            '${wrfBaseUnitsToDisplay(after.abs().toString())} WRF',
      if (balance == null) _balanceUnavailable,
      if (after != null && after.isNegative)
        'Insufficient balance: short by ${wrfBaseUnitsToDisplay((-after).toString())} WRF',
    ];
    return AlertDialog(
      title: const Text('Confirm Send'),
      content: Text(lines.join('\n')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (canSend)
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send'),
          ),
      ],
    );
  }
}

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  final _labelController = TextEditingController();

  String _privacyLevel = 'standard';
  bool _sending = false;
  bool _attemptInFlight = false;
  bool _previousTransferPending = false;
  bool _saveRecipient = false;
  bool _readingFee = true;
  TransferFeeQuote _fee = TransferFeeQuote.unknown;
  int _feeRequestId = 0;
  String? _ownLegacyAlias;

  @override
  void initState() {
    super.initState();
    ref.read(keyManagerProvider).getOwnLegacyAlias().then((alias) {
      if (mounted) setState(() => _ownLegacyAlias = alias);
    });
    _addressController.addListener(_onInputChanged);
    _amountController.addListener(_onInputChanged);
    _readFee();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  /// Signed transfers accept only core4 hex addresses
  /// (backend `isLaunchAddress`).
  bool _isValidAddress(String value) =>
      RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(value.trim());

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  /// Reads the network fee. Any failure leaves it unknown, which stops Send.
  Future<void> _readFee() async {
    final requestId = ++_feeRequestId;
    if (mounted) {
      setState(() {
        _readingFee = true;
        _fee = TransferFeeQuote.unknown;
      });
    }
    var quote = TransferFeeQuote.unknown;
    try {
      final from = await ref.read(keyManagerProvider).getAddress();
      if (!mounted) return;
      if (from != null) {
        final result = await ref
            .read(walletRepositoryProvider)
            .getTransferFee(from);
        quote = result.getOrElse((_) => TransferFeeQuote.unknown);
      }
    } catch (_) {
      // A wallet read that throws leaves the fee unknown, so Send stops.
    }
    if (!mounted || requestId != _feeRequestId) return;
    setState(() {
      _readingFee = false;
      _fee = quote;
    });
  }

  Future<bool> _trySocialSubmission({
    required String from,
    required String to,
    required String amount,
    required String? memo,
  }) async {
    final repo = ref.read(walletRepositoryProvider);
    final userOp = buildSponsoredUserOperation(
      from: from,
      to: to,
      amount: amount,
      memo: memo,
    );

    final sponsor = await repo.sponsorGas(walletAddress: from, userOp: userOp);
    return sponsor.fold((_) async => false, (sponsorData) async {
      final sponsoredOp = {
        ...userOp,
        'paymasterAndData': sponsorData['paymasterAndData'],
      };

      final submitted = await repo.submitUserOp(userOp: sponsoredOp);
      return submitted.fold((_) => false, (_) => true);
    });
  }

  String? _balanceProblem(String amountBaseUnits, {required bool sponsored}) {
    final balance = _walletBalanceUnits(ref.read(walletProvider));
    if (balance == null) return _balanceUnavailable;
    final reserve = sponsored ? BigInt.zero : _fee.reserveBaseUnits;
    if (reserve == null) return kNetworkFeeUnavailable;
    return BigInt.parse(amountBaseUnits) + reserve > balance
        ? 'Insufficient balance'
        : null;
  }

  List<AddressBookEntry> get _book =>
      ref.read(addressBookProvider).value ?? const <AddressBookEntry>[];

  AddressBookEntry? _contactFor(String to) {
    final target = to.trim().toLowerCase();
    for (final entry in _book) {
      if (entry.address.toLowerCase() == target) return entry;
    }
    return null;
  }

  /// Reassesses [to] (the immutable destination captured for this attempt)
  /// against fresh knowledge. Returns true, after telling the user, when it
  /// is a known legacy receive-only address and the send must stop.
  Future<bool> _blockedAsLegacy(KeyManager keyManager, String to) async {
    final alias = await keyManager.getOwnLegacyAlias();
    final assessment = assessRecipient(
      to: to,
      addressBook: _book,
      ownLegacyAlias: alias,
    );
    if (!assessment.blocksSend) return false;
    if (mounted) {
      setState(() => _ownLegacyAlias = alias);
      AppSnackbars.error(
        context,
        ValidationFailure(assessment.reason ?? 'Legacy address'),
      );
    }
    return true;
  }

  Future<void> _send() async {
    if (_attemptInFlight) return;
    // Freeze the destination field for the whole attempt.
    setState(() => _attemptInFlight = true);
    try {
      await _sendAttempt();
    } finally {
      if (mounted) setState(() => _attemptInFlight = false);
    }
  }

  Future<void> _sendAttempt() async {
    // Defence in depth: never submit from a build with Send disabled.
    if (!ref.read(walletSendEnabledProvider)) return;
    // The validator needs a fee, so a failed earlier read gets a new try here.
    if (_fee.state == TransferFeeState.unknown) await _readFee();
    if (!mounted) return;
    if (!_formKey.currentState!.validate()) return;

    final keyManager = ref.read(keyManagerProvider);

    // Capture the destination once; every later check and the submission use
    // this value, never the (editable) controller.
    final to = _addressController.text.trim();

    // A positively known legacy receive-only destination is never sent to.
    if (await _blockedAsLegacy(keyManager, to)) return;
    if (!await keyManager.canSignTransactions()) {
      if (mounted) {
        AppSnackbars.error(
          context,
          const ValidationFailure(
            'This legacy wallet is receive-only. Import its recovery phrase to create a canonical ed25519 wallet before sending.',
          ),
        );
      }
      return;
    }

    // The amount validator guarantees this converts; never round or use
    // floating point for the signed amount.
    if (!mounted) return;
    final amountBaseUnits = wrfDisplayToBaseUnits(_amountController.text);
    if (amountBaseUnits == null) return;

    // Re-check after the asynchronous signing-capability read, before PIN.
    if (!_formKey.currentState!.validate()) return;

    // Biometric-gated read of the ed25519 seed that signs the transfer.
    final privateKey = await keyManager.getPrivateKey();
    if (privateKey == null || privateKey.isEmpty) {
      if (mounted) {
        AppSnackbars.error(
          context,
          const AuthFailure('Authentication required to send'),
        );
      }
      return;
    }
    final Ed25519TransferSigner signer;
    try {
      signer = await Ed25519TransferSigner.fromSeedHex(privateKey);
    } on ArgumentError {
      if (mounted) {
        AppSnackbars.error(
          context,
          const ValidationFailure('This wallet key cannot sign transfers.'),
        );
      }
      return;
    }

    final from = await keyManager.getAddress();
    if (from == null) return;

    final isSocial = await sponsoredSendEnabled(
      () => ref.read(socialWalletProvider.future),
    );
    // Finish a fresh fee read after PIN; confirmation uses this final figure.
    if (!isSocial) await _readFee();
    if (!mounted) return;

    // Fresh knowledge about the captured destination, right before confirming.
    if (await _blockedAsLegacy(keyManager, to)) return;
    if (!mounted) return;
    final amount = wrfBaseUnitsToDisplay(amountBaseUnits)!;
    final memo = _memoController.text.trim().isEmpty
        ? null
        : _memoController.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SendConfirmationDialog(
        to: to,
        amountBaseUnits: amountBaseUnits,
        fee: _fee,
        sponsored: isSocial,
        contact: _contactFor(to),
      ),
    );
    if (confirmed != true || !mounted) return;
    // Knowledge may have changed while the user reviewed the dialog; recheck
    // the exact confirmed destination before anything is submitted.
    if (await _blockedAsLegacy(keyManager, to)) return;
    if (!mounted) return;
    // Wallet or fee may have changed while the user reviewed the dialog.
    final balanceProblem = _balanceProblem(
      amountBaseUnits,
      sponsored: isSocial,
    );
    if (balanceProblem != null) {
      AppSnackbars.error(context, ValidationFailure(balanceProblem));
      return;
    }

    setState(() {
      _sending = true;
      _previousTransferPending = false;
    });

    // Defensive: even if a non-standard tier were somehow selected, never route
    // through the private-send path while the tiers are gated off for launch
    // (backend /send-private returns 501 until core4#2080 revives the pool).
    final usePrivacy =
        kEnhancedPrivacyTiersEnabled && _privacyLevel != 'standard';

    Map<String, dynamic>? submissionResponse;
    try {
      if (usePrivacy) {
        await ref
            .read(walletProvider.notifier)
            .sendPrivateTransaction(
              from: from,
              recipientAddress: to,
              amount: amount,
              privacyLevel: _privacyLevel,
              memo: memo,
            );
      } else if (isSocial) {
        final userOpSubmitted = await _trySocialSubmission(
          from: from,
          to: to,
          amount: amount,
          memo: memo,
        );

        if (!userOpSubmitted) {
          submissionResponse = await ref
              .read(walletProvider.notifier)
              .sendTransaction(
                from: from,
                to: to,
                amountBaseUnits: amountBaseUnits,
                signer: signer,
              );
        }
      } else {
        submissionResponse = await ref
            .read(walletProvider.notifier)
            .sendTransaction(
              from: from,
              to: to,
              amountBaseUnits: amountBaseUnits,
              signer: signer,
            );
      }

      if (mounted) {
        setState(() => _sending = false);
        // Only the returned identifier is shown. Submission is not settlement,
        // and neither the receipt nor transfer details go to telemetry.
        final identifier = _submissionIdentifier(submissionResponse);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Submission receipt'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Submitted. Settlement has not been verified.'),
                const SizedBox(height: 12),
                if (identifier != null) ...[
                  const Text('Transaction identifier'),
                  SelectableText(identifier),
                ] else
                  const Text(
                    'Transaction identifier unavailable. Check wallet history before sending again.',
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }

      // Optional local bookkeeping and read refreshes follow the receipt;
      // their failures cannot turn submission into an apparent send failure.
      if (!mounted) return;
      if (_saveRecipient && _labelController.text.trim().isNotEmpty) {
        try {
          await ref
              .read(addressBookProvider.notifier)
              .addEntry(
                AddressBookEntry(
                  label: _labelController.text.trim(),
                  address: to,
                ),
              );
        } catch (_) {
          // A local address-book write says nothing about transaction outcome.
        }
      }

      if (!mounted) return;
      ref.invalidate(walletProvider);
      ref.invalidate(transactionsProvider);
      if (mounted && context.canPop()) context.pop();
    } catch (e) {
      if (e is Failure && e.statusCode == 409) {
        if (mounted) setState(() => _previousTransferPending = true);
        return;
      }
      if (mounted) {
        AppSnackbars.error(
          context,
          e is Failure ? e : ServerFailure(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _submissionIdentifier(Map<String, dynamic>? response) {
    // The deployed backend emits hash; tx_id supports a direct transaction
    // response. Do not print arbitrary payload fields or malformed identifiers.
    for (final key in ['hash', 'tx_id']) {
      final value = response?[key];
      if (value is String &&
          RegExp(r'^(?:0x)?[0-9a-fA-F]{64}$').hasMatch(value)) {
        return value;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // The route and the wallet button are gated too; this covers any other
    // way the screen could be built (WalletSendGate).
    if (!ref.watch(walletSendEnabledProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Send')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sending is disabled in this test build.',
              key: Key('wallet-send-disabled'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final socialAsync = ref.watch(socialWalletProvider);
    ref.watch(walletProvider);
    final addressBookAsync = ref.watch(addressBookProvider);

    final entries = addressBookAsync.value ?? const <AddressBookEntry>[];
    final input = _addressController.text.trim().toLowerCase();
    final assessment = assessRecipient(
      to: _addressController.text,
      addressBook: entries,
      ownLegacyAlias: _ownLegacyAlias,
    );
    final suggestions = entries
        .where((entry) {
          if (input.isEmpty) return true;
          return entry.label.toLowerCase().contains(input) ||
              entry.address.toLowerCase().contains(input);
        })
        .take(5)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (_previousTransferPending) ...[
                const Text(pendingTransferMessage),
                const SizedBox(height: 16),
              ],
              if (kSponsoredSendEnabled && socialAsync.value == true)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.local_gas_station, color: AppColors.success),
                      SizedBox(width: 8),
                      Text('Free transfer'),
                    ],
                  ),
                ),
              if (kSponsoredSendEnabled && socialAsync.value == true)
                const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                readOnly: _attemptInFlight || _sending,
                decoration: const InputDecoration(
                  labelText: 'Send to',
                  hintText: '0x...',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Address required';
                  if (!_isValidAddress(v)) {
                    return 'Must be a 0x... address';
                  }
                  return null;
                },
              ),
              if (assessment.blocksSend) ...[
                const SizedBox(height: 8),
                Container(
                  key: const Key('legacy-recipient-blocked'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send blocked: legacy receive-only address',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(assessment.reason ?? ''),
                      if (assessment.replacement != null) ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: const Key('use-replacement-address'),
                          onPressed: () {
                            _addressController.text = assessment.replacement!;
                            setState(() {});
                          },
                          child: Text(
                            'Use verified address ${assessment.replacement}',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final entry in suggestions)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.label),
                    subtitle: Text(
                      entry.address,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    trailing: Text(switch (entry.status) {
                      AddressStatus.knownLegacy => 'legacy',
                      AddressStatus.verifiedCurrent => 'current',
                      AddressStatus.unverified => 'unverified',
                    }),
                    onTap: () {
                      _addressController.text = entry.address;
                      setState(() {});
                    },
                  ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount (WRF)',
                  hintText: '0.00',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Amount required';
                  if (wrfDisplayIsAmbiguous(v)) {
                    return 'Ambiguous amount: use a dot for decimals (e.g. 1.000)';
                  }
                  // Exact base-unit conversion: at most 8 decimals, positive,
                  // and within the backend's JSON-safe integer limit.
                  final units = wrfDisplayToBaseUnits(v);
                  if (units == null) {
                    return 'Invalid amount';
                  }
                  return _balanceProblem(
                    units,
                    sponsored:
                        kSponsoredSendEnabled && socialAsync.value == true,
                  );
                },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                // Follows the app theme: a fixed dark box hid the fee on light.
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kSponsoredSendEnabled && socialAsync.value == true
                            ? 'Network fee: Free transfer'
                            : _readingFee
                            ? 'Checking network fee...'
                            : _fee.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (!_readingFee && _fee.state == TransferFeeState.unknown)
                      TextButton(
                        key: const Key('retry-network-fee'),
                        onPressed: _readFee,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _privacyLevel,
                decoration: const InputDecoration(labelText: 'Privacy Level'),
                // Enhanced/Maximum tiers are hidden for launch — see
                // kEnhancedPrivacyTiersEnabled (re-enable via core4#2080).
                items: const [
                  DropdownMenuItem(value: 'standard', child: Text('Standard')),
                  if (kEnhancedPrivacyTiersEnabled) ...[
                    DropdownMenuItem(
                      value: 'enhanced',
                      child: Text('Enhanced'),
                    ),
                    DropdownMenuItem(value: 'maximum', child: Text('Maximum')),
                  ],
                ],
                onChanged: (v) =>
                    setState(() => _privacyLevel = v ?? 'standard'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _memoController,
                decoration: const InputDecoration(
                  labelText: 'Memo (optional)',
                  helperText: 'Not included in the signed transfer',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _saveRecipient,
                onChanged: (value) =>
                    setState(() => _saveRecipient = value ?? false),
                title: const Text('Save recipient to address book'),
              ),
              if (_saveRecipient)
                TextFormField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: 'Address label',
                    hintText: 'e.g. Savings wallet',
                  ),
                  validator: (value) {
                    if (_saveRecipient &&
                        (value == null || value.trim().isEmpty)) {
                      return 'Label required to save address';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Biometric authentication required before sending',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
