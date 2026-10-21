import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/crypto/wallet_secure_storage.dart';
import '../../../../services/crypto/wallet_setup_service.dart';
import '../../../../services/referral/referral_service.dart';
import '../../../../services/security/screen_security_service.dart';
import '../../../../services/security/secure_clipboard_service.dart';
import '../providers/transactions_provider.dart';
import '../providers/wallet_provider.dart';

class CreateWalletScreen extends ConsumerStatefulWidget {
  const CreateWalletScreen({super.key});

  @override
  ConsumerState<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends ConsumerState<CreateWalletScreen>
    with WidgetsBindingObserver {
  late final ScreenSecurityService _screenSecurityService;
  late final SecureClipboardService _secureClipboard;
  WalletCredentials? _credentials;
  List<int> _verificationIndexes = const [];
  final Map<int, TextEditingController> _verificationControllers = {};
  bool _generated = false;
  bool _saving = false;
  bool _generationFailed = false;

  // The phrase stays on screen until the user hides it or leaves (mobile#320:
  // a timer that wiped it after 60 s also wiped the unsaved wallet). Hiding
  // is separate from the lifecycle obscure, and neither touches the
  // credentials or the verification below.
  bool _hiddenByUser = false;
  bool _obscuredByLifecycle = false;

  /// Label of a copied phrase still to be cleared from the clipboard.
  String? _pendingClipLabel;
  Timer? _clipClearTimer;
  bool _clipClearDue = false;
  static const _clipClearDelay = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _screenSecurityService = ref.read(screenSecurityServiceProvider);
    _secureClipboard = ref.read(secureClipboardServiceProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clipClearTimer?.cancel();
    final label = _pendingClipLabel;
    if (label != null) {
      unawaited(_secureClipboard.clearIfOurs(label));
    }
    _credentials = null;
    _screenSecurityService.disableProtection();
    for (final controller in _verificationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      setState(() => _obscuredByLifecycle = true);
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _obscuredByLifecycle = false);
      if (_clipClearDue) _clearClip();
    }
  }

  Future<void> _generateWallet() async {
    setState(() {
      _generated = false;
      _generationFailed = false;
      _hiddenByUser = false;
    });
    await _clearClip();

    try {
      final service = ref.read(walletSetupServiceProvider);
      final credentials = await service.generateWallet();
      final words = credentials.mnemonic.split(RegExp(r'\s+'));
      final indexes = service.pickVerificationIndexes(words.length, count: 3);

      if (!mounted) return;
      // The native flag must settle before any frame can contain the phrase.
      await _screenSecurityService.enableProtection();
      if (!mounted) {
        await _screenSecurityService.disableProtection();
        return;
      }

      for (final controller in _verificationControllers.values) {
        controller.dispose();
      }
      _verificationControllers
        ..clear()
        ..addEntries(
          indexes.map((index) => MapEntry(index, TextEditingController())),
        );

      if (!mounted) return;
      setState(() {
        _credentials = credentials;
        _verificationIndexes = indexes;
        _generated = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _generationFailed = true;
      });
    }
  }

  Future<void> _copyPhrase() async {
    final credentials = _credentials;
    if (credentials == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy recovery phrase?'),
        content: const Text(
          'Anyone who sees these words can take your wallet. Other apps '
          'and a clipboard history can read what you copy. Paste the phrase '
          'only into a password manager you trust. The clipboard is cleared '
          'again in 60 seconds.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Copy anyway'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _clearClip();
    final label = SecureClipboardService.newLabel();
    final copied = await _secureClipboard.copySensitive(
      text: credentials.mnemonic,
      label: label,
    );
    if (!mounted) return;
    if (!copied) {
      AppSnackbars.error(
        context,
        const ValidationFailure('Copy is not available on this device.'),
      );
      return;
    }
    _pendingClipLabel = label;
    _clipClearDue = false;
    _clipClearTimer?.cancel();
    _clipClearTimer = Timer(_clipClearDelay, _clearClip);
    AppSnackbars.success(
      context,
      'Recovery phrase copied. The clipboard is cleared in 60 seconds.',
    );
  }

  /// Clears a copied phrase if the clipboard still holds it. When the app is
  /// in the background the clipboard cannot be checked, so the clear runs
  /// again on resume (and on leaving the screen).
  Future<void> _clearClip() async {
    _clipClearTimer?.cancel();
    _clipClearTimer = null;
    final label = _pendingClipLabel;
    if (label == null) return;
    final result = await _secureClipboard.clearIfOurs(label);
    if (result == ClearResult.done) {
      if (_pendingClipLabel == label) _pendingClipLabel = null;
      _clipClearDue = false;
    } else {
      _clipClearDue = true;
    }
  }

  bool get _isVerificationValid {
    final credentials = _credentials;
    if (credentials == null) return false;

    final service = ref.read(walletSetupServiceProvider);
    final responses = {
      for (final entry in _verificationControllers.entries)
        entry.key: entry.value.text,
    };
    return service.verifyMnemonicSelections(
      mnemonic: credentials.mnemonic,
      indexes: _verificationIndexes,
      responses: responses,
    );
  }

  Future<void> _saveWallet() async {
    final credentials = _credentials;
    if (credentials == null || !_isVerificationValid || _saving) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(keyManagerProvider)
          .storeKeys(
            mnemonic: credentials.mnemonic,
            privateKey: credentials.privateKey,
            address: credentials.address,
            keyScheme: credentials.keyScheme,
            loginPrivateKey: credentials.loginPrivateKey,
            loginAddress: credentials.loginAddress,
          );

      await ref.read(walletSecureStorageProvider).setBackupConfirmed(true);
      await ref.read(walletSecureStorageProvider).setIsSocial(false);
      // Creating the wallet is the one moment that signs in on its own:
      // one biometric prompt, one nonce, one login (mobile#320). Anything
      // else waits for the user's Sign in. A failure here is not a failed
      // setup; the wallet screen then offers Sign in.
      try {
        await ref.read(apiClientProvider).signInNow();
      } catch (_) {}
      await ref
          .read(referralServiceProvider)
          .trackReferralAttributionOnSignup(
            refereeAddress: credentials.address,
          );

      ref.invalidate(walletProvider);
      ref.invalidate(transactionsProvider);

      _credentials = null;
      await _screenSecurityService.disableProtection();

      if (!mounted) return;
      AppSnackbars.success(context, 'Wallet created successfully');
      context.go('/wallet');
    } catch (e) {
      if (!mounted) return;
      AppSnackbars.error(context, ServerFailure(e.toString()));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final credentials = _credentials;
    final mnemonicWords =
        credentials?.mnemonic.split(RegExp(r'\s+')) ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Create Wallet')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text(
              'Your wallet will be generated securely on this device.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _saving ? null : _generateWallet,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Generate Wallet'),
            ),
            if (_generationFailed) ...[
              const SizedBox(height: 12),
              const Text(
                'Unable to generate wallet. Please try again.',
                style: TextStyle(color: AppColors.error),
              ),
            ],
            if (_generated && credentials != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Recovery phrase (12 words)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (_obscuredByLifecycle)
                const _PhrasePlaceholder(
                  'Recovery phrase hidden — return to app to view',
                )
              else if (_hiddenByUser)
                const _PhrasePlaceholder('Recovery phrase hidden')
              else
                _PhraseWords(words: mnemonicWords),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  if (_hiddenByUser)
                    TextButton.icon(
                      onPressed: () => setState(() => _hiddenByUser = false),
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text('Show words'),
                    )
                  else ...[
                    TextButton.icon(
                      key: const Key('create-wallet-copy'),
                      onPressed: _obscuredByLifecycle ? null : _copyPhrase,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _hiddenByUser = true),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text("I've written it down"),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Verify these words to confirm your backup:',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              ..._verificationIndexes.map((index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _verificationControllers[index],
                    decoration: InputDecoration(
                      labelText: 'Word #${index + 1}',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                );
              }),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isVerificationValid && !_saving
                    ? _saveWallet
                    : null,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Complete Setup'),
              ),
              const SizedBox(height: 8),
              Text(
                'Address: ${credentials.address}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
            if (mnemonicWords.length != 12 && mnemonicWords.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Warning: generated phrase is not 12 words.',
                style: TextStyle(color: AppColors.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhraseWords extends StatelessWidget {
  const _PhraseWords({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          for (var i = 0; i < words.length; i++)
            SizedBox(
              width: 120,
              child: Text(
                '${i + 1}. ${words[i]}',
                style: const TextStyle(height: 1.5, fontFamily: 'monospace'),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhrasePlaceholder extends StatelessWidget {
  const _PhrasePlaceholder(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
