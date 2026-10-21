import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../services/auth/biometric_service.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/crypto/wallet_secure_storage.dart';
import '../../../../services/crypto/wallet_setup_service.dart';
import '../../../../services/referral/referral_service.dart';
import '../../../../services/security/screen_security_service.dart';
import '../providers/transactions_provider.dart';
import '../providers/wallet_provider.dart';

enum _ImportType { mnemonic, privateKey }

class ImportWalletScreen extends ConsumerStatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  ConsumerState<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends ConsumerState<ImportWalletScreen> {
  late final ScreenSecurityService _screenSecurityService;
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController();
  _ImportType _importType = _ImportType.mnemonic;
  WalletCredentials? _pendingCredentials;
  List<int> _verificationIndexes = const [];
  final Map<int, TextEditingController> _verificationControllers = {};
  bool _importing = false;
  bool _saving = false;
  bool _awaitingVerification = false;

  @override
  void initState() {
    super.initState();
    _screenSecurityService = ref.read(screenSecurityServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _screenSecurityService.enableProtection();
    });
  }

  @override
  void dispose() {
    _valueController.clear();
    _valueController.dispose();
    _clearVerificationControllers();
    _screenSecurityService.disableProtection();
    super.dispose();
  }

  void _clearVerificationControllers() {
    for (final controller in _verificationControllers.values) {
      controller.dispose();
    }
    _verificationControllers.clear();
  }

  void _resetRecoveryState() {
    _pendingCredentials = null;
    _verificationIndexes = const [];
    _awaitingVerification = false;
    _clearVerificationControllers();
  }

  bool get _isVerificationValid {
    final credentials = _pendingCredentials;
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

  Future<void> _storeWallet(WalletCredentials credentials) async {
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
    await ref
        .read(referralServiceProvider)
        .trackReferralAttributionOnSignup(refereeAddress: credentials.address);

    ref.invalidate(walletProvider);
    ref.invalidate(transactionsProvider);
  }

  Future<void> _finishImport(String successMessage) async {
    if (!mounted) return;
    AppSnackbars.success(context, successMessage);
    context.go('/wallet');
  }

  Future<void> _importWallet() async {
    if (!_formKey.currentState!.validate() ||
        _importing ||
        _saving ||
        _awaitingVerification) {
      return;
    }

    setState(() => _importing = true);
    try {
      final service = ref.read(walletSetupServiceProvider);
      final value = _valueController.text.trim();

      final credentials = switch (_importType) {
        _ImportType.mnemonic => await service.importFromMnemonic(value),
        _ImportType.privateKey => await service.importFromPrivateKey(value),
      };

      if (_importType == _ImportType.mnemonic) {
        final words = credentials.mnemonic.split(RegExp(r'\s+'));
        final indexes = service.pickVerificationIndexes(words.length, count: 3);

        _clearVerificationControllers();
        for (final index in indexes) {
          _verificationControllers[index] = TextEditingController();
        }

        if (!mounted) return;
        setState(() {
          _pendingCredentials = credentials;
          _verificationIndexes = indexes;
          _awaitingVerification = true;
        });
        _valueController.clear();
        return;
      }

      await _storeWallet(credentials);
      _valueController.clear();
      await _finishImport(
        credentials.keyScheme == KeyManager.legacyKeyScheme
            ? 'Legacy private key imported in receive-only mode. It was not re-keyed.'
            : 'Wallet imported successfully',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbars.error(context, ServerFailure(e.toString()));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _completeRecovery() async {
    final credentials = _pendingCredentials;
    if (credentials == null || !_isVerificationValid || _saving) return;

    final authenticated = await ref
        .read(biometricServiceProvider)
        .authenticate(reason: 'Authenticate to complete wallet recovery');
    if (!authenticated) {
      if (!mounted) return;
      AppSnackbars.error(
        context,
        const AuthFailure('Biometric authentication required'),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _storeWallet(credentials);
      _resetRecoveryState();
      _valueController.clear();
      await _finishImport('Wallet restored securely');
    } catch (e) {
      if (!mounted) return;
      AppSnackbars.error(context, ServerFailure(e.toString()));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final awaitingVerification = _awaitingVerification;
    final pendingCredentials = _pendingCredentials;

    return Scaffold(
      appBar: AppBar(title: const Text('Import / Restore Wallet')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              SegmentedButton<_ImportType>(
                segments: const [
                  ButtonSegment(
                    value: _ImportType.mnemonic,
                    icon: Icon(Icons.notes),
                    label: Text('Mnemonic'),
                  ),
                  ButtonSegment(
                    value: _ImportType.privateKey,
                    icon: Icon(Icons.key),
                    label: Text('Private Key'),
                  ),
                ],
                selected: {_importType},
                onSelectionChanged: awaitingVerification
                    ? null
                    : (value) {
                        setState(() {
                          _importType = value.first;
                          _valueController.clear();
                          _resetRecoveryState();
                        });
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _valueController,
                maxLines: _importType == _ImportType.mnemonic ? 3 : 1,
                obscureText: _importType == _ImportType.privateKey,
                enabled: !awaitingVerification,
                decoration: InputDecoration(
                  labelText: _importType == _ImportType.mnemonic
                      ? 'Recovery Phrase'
                      : 'Private Key',
                  hintText: _importType == _ImportType.mnemonic
                      ? 'word1 word2 ... word12'
                      : '0x... or raw key',
                ),
                validator: (value) {
                  final input = value?.trim() ?? '';
                  if (input.isEmpty) {
                    return _importType == _ImportType.mnemonic
                        ? 'Recovery phrase required'
                        : 'Private key required';
                  }

                  if (_importType == _ImportType.mnemonic &&
                      input.split(RegExp(r'\s+')).length < 12) {
                    return 'Expected 12-word phrase';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _importing || awaitingVerification
                    ? null
                    : _importWallet,
                child: _importing && !awaitingVerification
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _importType == _ImportType.mnemonic
                            ? 'Verify Recovery'
                            : 'Import Wallet',
                      ),
              ),
              if (_importType == _ImportType.mnemonic &&
                  awaitingVerification &&
                  pendingCredentials != null) ...[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Confirm recovery phrase',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Verify sampled words before this wallet is stored on this device.',
                        ),
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () {
                                        setState(() {
                                          _resetRecoveryState();
                                          _valueController.clear();
                                        });
                                      },
                                child: const Text('Start over'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isVerificationValid && !_saving
                                    ? _completeRecovery
                                    : null,
                                child: _saving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Complete Recovery'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your recovery phrase stays in memory only until verification completes.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
