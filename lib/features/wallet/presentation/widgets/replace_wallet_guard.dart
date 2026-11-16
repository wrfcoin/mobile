import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../services/auth/biometric_service.dart';
import '../../../../services/crypto/key_manager.dart';

/// Stands in front of Create and Import when this phone already has a wallet.
///
/// Saving a new wallet replaces the stored one, and without its recovery
/// words the old wallet and its WRF are gone for good. So the user sees that
/// first, "Keep my wallet" is the default, and replacing needs the device
/// unlock. On a phone with no wallet [child] shows straight away.
class ReplaceWalletGuard extends ConsumerStatefulWidget {
  const ReplaceWalletGuard({super.key, required this.child, this.leading});

  final Widget child;

  /// The app bar's back button, when the route needs its own.
  final Widget? leading;

  static const keepKey = Key('replace-wallet-keep');
  static const replaceKey = Key('replace-wallet-replace');

  @override
  ConsumerState<ReplaceWalletGuard> createState() => _ReplaceWalletGuardState();
}

enum _GuardState { checking, existingWallet, open }

class _ReplaceWalletGuardState extends ConsumerState<ReplaceWalletGuard> {
  _GuardState _state = _GuardState.checking;
  String? _address;
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final keys = ref.read(keyManagerProvider);
    var existing = true;
    String? address;
    try {
      existing = await keys.hasWallet();
      if (existing) address = await keys.getAddress();
    } catch (_) {
      // A store that cannot be read may still hold a wallet: ask first.
      existing = true;
    }
    if (!mounted) return;
    setState(() {
      _address = address;
      _state = existing ? _GuardState.existingWallet : _GuardState.open;
    });
  }

  void _keep() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/wallet');
    }
  }

  Future<void> _replace() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);
    final unlocked = await ref
        .read(biometricServiceProvider)
        .authenticate(reason: 'Unlock to replace the wallet on this phone');
    if (!mounted) return;
    setState(() {
      _unlocking = false;
      if (unlocked) _state = _GuardState.open;
    });
    if (!unlocked) {
      AppSnackbars.error(
        context,
        const ValidationFailure(
          'The phone was not unlocked, so your wallet was not changed.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GuardState.open:
        return widget.child;
      case _GuardState.checking:
        return Scaffold(
          appBar: AppBar(leading: widget.leading),
          body: const Center(child: CircularProgressIndicator()),
        );
      case _GuardState.existingWallet:
        return _ExistingWalletView(
          address: _address,
          leading: widget.leading,
          unlocking: _unlocking,
          onKeep: _keep,
          onReplace: _replace,
        );
    }
  }
}

/// `0xABCD…1234`: enough to recognise an address, short enough to read.
String shortWalletAddress(String address) {
  final a = address.trim();
  if (a.length <= 12) return a;
  return '${a.substring(0, 6)}…${a.substring(a.length - 4)}';
}

class _ExistingWalletView extends StatelessWidget {
  const _ExistingWalletView({
    required this.address,
    required this.leading,
    required this.unlocking,
    required this.onKeep,
    required this.onReplace,
  });

  final String? address;
  final Widget? leading;
  final bool unlocking;
  final VoidCallback onKeep;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final which = address == null ? '' : ' (${shortWalletAddress(address!)})';
    return Scaffold(
      appBar: AppBar(leading: leading, title: const Text('Wallet')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'This phone already has a wallet$which.',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Making or importing another one replaces it here. Without '
                'its recovery words or private key, the old wallet and its '
                'WRF are gone for good.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              FilledButton(
                key: ReplaceWalletGuard.keepKey,
                onPressed: onKeep,
                child: const Text('Keep my wallet'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: ReplaceWalletGuard.replaceKey,
                onPressed: unlocking ? null : onReplace,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text(
                  'I have my recovery words or key saved, replace it',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
