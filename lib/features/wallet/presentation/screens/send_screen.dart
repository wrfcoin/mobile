import 'dart:async';

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
import '../../data/models/wallet_model.dart';
import '../../domain/recipient_safety.dart';
import '../../domain/send_allowlist.dart';
import '../../../../services/crypto/wallet_secure_storage.dart';
import '../../data/repositories/wallet_repository_impl.dart';
import '../providers/transactions_provider.dart';
import '../providers/wallet_provider.dart';
import '../providers/wallet_security_provider.dart';
import '../widgets/safety_notice.dart';

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

/// Title and detail for a Send the allowlist refuses.
@visibleForTesting
({String title, String body}) allowlistRefusal(AllowlistVerdict verdict) {
  final name = verdict.contact?.label;
  return switch (verdict.kind) {
    AllowlistVerdictKind.pending => (
      title: 'Not allowed yet',
      body:
          '"$name" can be used from '
          '${formatAllowlistTime(verdict.allowedFrom!)}.',
    ),
    AllowlistVerdictKind.notAllowed => (
      title: 'Not on your allowlist',
      body:
          '"$name" is saved but not allowed. Allowing a contact takes 24 '
          'hours while the allowlist is on.',
    ),
    _ => (
      title: 'Not on your allowlist',
      body:
          'Your send allowlist is on, and this address is not one of your '
          'contacts. Save it and allow it; it can be used 24 hours later.',
    ),
  };
}

/// Shown whenever no usable `feeBaseUnits` figure is available.
const String kFeeEstimateUnavailable = 'Fee estimate unavailable';

/// Label for a fee already formatted as display WRF, or
/// [kFeeEstimateUnavailable] when there is none.
@visibleForTesting
String feeLabel({required String? feeWrf, required bool authoritative}) {
  if (feeWrf == null || feeWrf.trim().isEmpty) {
    return kFeeEstimateUnavailable;
  }
  return authoritative
      ? 'Network fee: $feeWrf WRF'
      : 'Fee estimate: $feeWrf WRF (non-authoritative, not charged on chain)';
}

/// Reads the `POST /wallet/estimate-gas` response (backend #1200) and returns
/// its `feeBaseUnits` formatted as display WRF.
///
/// Returns `null` when `feeBaseUnits` is missing or not an integer string, or
/// when the echoed `amountBaseUnits` differs from [requestedBaseUnits]. A
/// WRF-formatted `fee` field is ignored: the contract no longer sends one.
@visibleForTesting
String? feeWrfFromEstimate(
  Map<String, dynamic> response, {
  required String requestedBaseUnits,
}) {
  final fee = response['feeBaseUnits'];
  if (fee is! String) return null;
  final echoed = response['amountBaseUnits'];
  if (echoed != null && echoed != requestedBaseUnits) return null;
  return wrfBaseUnitsToDisplay(fee);
}

BigInt? _walletBalanceUnits(AsyncValue<WalletModel?> wallet) {
  // Do not use retained data during a refresh or after a failed read.
  if (wallet.isLoading || wallet.hasError) return null;
  final balance = wallet.value?.balance;
  if (balance == null || wrfBaseUnitsToDisplay(balance) == null) return null;
  return BigInt.parse(balance.trim());
}

const _balanceUnavailable = 'Balance unavailable — refresh and try again';
const _networkFeeUnavailable = 'Network fee unavailable — try again';

/// Reads the same provider as WalletScreen, including changes while open.
class SendConfirmationDialog extends ConsumerWidget {
  const SendConfirmationDialog({
    super.key,
    required this.to,
    required this.amountBaseUnits,
    this.feeBaseUnits,
    this.authoritative = false,
    this.sponsored = false,
    this.contact,
  });

  final String to;
  final AddressBookEntry? contact;
  final String amountBaseUnits;
  final BigInt? feeBaseUnits;
  final bool authoritative;
  final bool sponsored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = _walletBalanceUnits(ref.watch(walletProvider));
    final amount = BigInt.parse(amountBaseUnits);
    final fee = sponsored ? BigInt.zero : feeBaseUnits;
    final after = balance == null || fee == null
        ? null
        : balance - amount - fee;
    final canSend = after != null && after >= BigInt.zero;
    final approximate = !sponsored && fee != null && !authoritative;
    final feeText = sponsored
        ? 'Network fee: Free transfer'
        : feeLabel(
            feeWrf: fee == null ? null : wrfBaseUnitsToDisplay(fee.toString()),
            authoritative: authoritative,
          );
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
      if (fee == null) _networkFeeUnavailable,
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
  bool _estimatingFee = false;
  String? _feePreview;
  BigInt? _feeBaseUnits;
  bool _feeAuthoritative = false;
  int _feeRequestId = 0;
  Timer? _feeDebounce;
  String? _ownLegacyAlias;

  @override
  void initState() {
    super.initState();
    ref.read(keyManagerProvider).getOwnLegacyAlias().then((alias) {
      if (mounted) setState(() => _ownLegacyAlias = alias);
    });
    _addressController.addListener(_scheduleFeeEstimate);
    _amountController.addListener(_scheduleFeeEstimate);
  }

  @override
  void dispose() {
    _feeDebounce?.cancel();
    _addressController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  /// Signed transfers and fee estimates accept only core4 hex addresses
  /// (backend `isLaunchAddress`).
  bool _isValidAddress(String value) => isSendableAddress(value);

  void _scheduleFeeEstimate() {
    _feeDebounce?.cancel();
    _feeRequestId++;
    if (mounted) {
      setState(() {
        _feePreview = null;
        _feeBaseUnits = null;
        _feeAuthoritative = false;
        _estimatingFee = false;
      });
    }
    _feeDebounce = Timer(const Duration(milliseconds: 450), _updateFeePreview);
  }

  Future<void> _updateFeePreview() async {
    final requestId = _feeRequestId;
    final amount = _amountController.text.trim();
    final to = _addressController.text.trim();
    if (amount.isEmpty || to.isEmpty || !_isValidAddress(to)) return;

    final from = await ref.read(keyManagerProvider).getAddress();
    if (from == null) return;

    // estimate-gas takes integer base units (backend #1200). An amount that
    // does not convert exactly is not sent; the label stays unavailable.
    final amountBaseUnits = wrfDisplayToBaseUnits(amount);
    if (amountBaseUnits == null) return;

    if (!mounted || requestId != _feeRequestId) return;
    setState(() => _estimatingFee = true);
    final repo = ref.read(walletRepositoryProvider);
    final result = await repo.estimateGas(
      from: from,
      to: to,
      amount: amountBaseUnits,
      memo: _memoController.text.trim().isEmpty
          ? null
          : _memoController.text.trim(),
    );

    // Drop responses for inputs the user has since changed.
    if (!mounted || requestId != _feeRequestId) return;

    result.fold(
      (_) => setState(() {
        _feePreview = null;
        _feeBaseUnits = null;
        _feeAuthoritative = false;
        _estimatingFee = false;
      }),
      (data) => setState(() {
        _feePreview = feeWrfFromEstimate(
          data,
          requestedBaseUnits: amountBaseUnits,
        );
        _feeBaseUnits = _feePreview == null
            ? null
            : BigInt.parse(data['feeBaseUnits'] as String);
        _feeAuthoritative =
            _feePreview != null && data['authoritative'] == true;
        _estimatingFee = false;
      }),
    );
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
    final fee = sponsored ? BigInt.zero : _feeBaseUnits;
    if (fee == null) return _networkFeeUnavailable;
    return BigInt.parse(amountBaseUnits) + fee > balance
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

  /// Legacy and allowlist checks against fresh local knowledge.
  Future<bool> _blocked(KeyManager keyManager, String to) async {
    if (await _blockedAsLegacy(keyManager, to)) return true;
    return _blockedByAllowlist(to);
  }

  /// Reads the allowlist and contacts from storage (not cached state), so a
  /// change made elsewhere is honoured. Returns true, after telling the
  /// user, when the send must stop.
  Future<bool> _blockedByAllowlist(String to) async {
    final settings = await ref.read(sendAllowlistProvider.notifier).current();
    final book = await ref.read(walletSecureStorageProvider).getAddressBook();
    final verdict = ref
        .read(sendAllowlistPolicyProvider)
        .check(to: to, book: book, settings: settings);
    if (!verdict.blocksSend) return false;
    if (mounted) {
      final refusal = allowlistRefusal(verdict);
      AppSnackbars.error(
        context,
        ValidationFailure('${refusal.title}. ${refusal.body}'),
      );
    }
    return true;
  }

  Future<void> _pickContact() async {
    final entries = ref.read(addressBookProvider).value ?? const [];
    final picked = await showModalBottomSheet<AddressBookEntry>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: entries.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No contacts yet. Add them in Contacts.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in entries)
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(entry.label),
                      subtitle: Text(
                        entry.address,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(entry),
                    ),
                ],
              ),
      ),
    );
    if (picked == null || !mounted) return;
    _addressController.text = picked.address;
    setState(() {});
    _scheduleFeeEstimate();
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
    if (!_formKey.currentState!.validate()) return;

    final keyManager = ref.read(keyManagerProvider);

    // Capture the destination once; every later check and the submission use
    // this value, never the (editable) controller.
    final to = _addressController.text.trim();

    // A positively known legacy receive-only destination is never sent to.
    if (await _blocked(keyManager, to)) return;
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
    _feeDebounce?.cancel();
    if (!isSocial) await _updateFeePreview();
    if (!mounted) return;

    // Fresh knowledge about the captured destination, right before confirming.
    if (await _blocked(keyManager, to)) return;
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
        feeBaseUnits: _feeBaseUnits,
        authoritative: _feeAuthoritative,
        sponsored: isSocial,
        contact: _contactFor(to),
      ),
    );
    if (confirmed != true || !mounted) return;
    // Knowledge may have changed while the user reviewed the dialog; recheck
    // the exact confirmed destination before anything is submitted.
    if (await _blocked(keyManager, to)) return;
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
    final allowlistSettings =
        ref.watch(sendAllowlistProvider).value ?? SendAllowlistSettings.off;
    final allowlistPolicy = ref.watch(sendAllowlistPolicyProvider);

    final entries = addressBookAsync.value ?? const <AddressBookEntry>[];
    final input = _addressController.text.trim().toLowerCase();
    final assessment = assessRecipient(
      to: _addressController.text,
      addressBook: entries,
      ownLegacyAlias: _ownLegacyAlias,
    );
    final allowlistOn = allowlistPolicy.isOn(allowlistSettings);
    final allowlistVerdict = allowlistOn && _isValidAddress(input)
        ? allowlistPolicy.check(
            to: input,
            book: entries,
            settings: allowlistSettings,
          )
        : null;
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
                decoration: InputDecoration(
                  labelText: 'Send to',
                  hintText: '0x...',
                  helperText: allowlistOn
                      ? 'Allowlist on: only allowed contacts'
                      : null,
                  suffixIcon: IconButton(
                    key: const Key('send-pick-contact'),
                    tooltip: 'Choose a contact',
                    icon: const Icon(Icons.contacts_outlined),
                    onPressed: _attemptInFlight || _sending
                        ? null
                        : _pickContact,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Address required';
                  if (!_isValidAddress(v)) {
                    return 'Must be a 0x... address';
                  }
                  return null;
                },
              ),
              // One slot for everything under the address field, so the
              // fields below keep their place (and state) as notices and
              // suggestions come and go.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                                _addressController.text =
                                    assessment.replacement!;
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
                  _AllowlistNotice(
                    verdict:
                        allowlistVerdict != null &&
                            allowlistVerdict.blocksSend &&
                            !assessment.blocksSend
                        ? allowlistVerdict
                        : null,
                  ),
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
                          _scheduleFeeEstimate();
                        },
                      ),
                  ],
                ],
              ),
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
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kSponsoredSendEnabled && socialAsync.value == true
                            ? 'Network fee: Free transfer'
                            : _estimatingFee
                            ? 'Estimating fee...'
                            : feeLabel(
                                feeWrf: _feePreview,
                                authoritative: _feeAuthoritative,
                              ),
                        style: const TextStyle(fontSize: 13),
                      ),
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

class _AllowlistNotice extends StatelessWidget {
  const _AllowlistNotice({required this.verdict});

  final AllowlistVerdict? verdict;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    if (v == null) return const SizedBox.shrink();
    final refusal = allowlistRefusal(v);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SafetyNotice(
        key: const Key('allowlist-recipient-blocked'),
        tone: SafetyTone.blocked,
        title: refusal.title,
        body: refusal.body,
        children: [
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push('/wallet/allowlist'),
              child: const Text('Open allowlist'),
            ),
          ),
        ],
      ),
    );
  }
}
