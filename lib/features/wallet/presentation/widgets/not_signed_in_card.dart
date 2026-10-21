import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/api/api_client.dart';
import '../providers/transactions_provider.dart';
import '../providers/wallet_provider.dart';

/// Earnings for a wallet without a session (mobile#320). It says "Not
/// signed in", not "Session expired", and offers the one action that signs
/// in: each tap is one biometric prompt, one nonce and one login, and
/// nothing retries on its own.
class NotSignedInCard extends ConsumerStatefulWidget {
  const NotSignedInCard({super.key, this.detail});

  /// Why, when the client said more (a lock, a cancelled prompt).
  final String? detail;

  @override
  ConsumerState<NotSignedInCard> createState() => _NotSignedInCardState();
}

class _NotSignedInCardState extends ConsumerState<NotSignedInCard> {
  bool _signingIn = false;

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    var ok = false;
    try {
      ok = await ref.read(apiClientProvider).signInNow();
    } catch (_) {
      // The client explains failures through the handoff message.
      ok = false;
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
    if (ok && mounted) {
      ref.invalidate(walletProvider);
      ref.invalidate(transactionsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_outline, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'Not signed in',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              detail != null && detail.isNotEmpty
                  ? detail
                  : 'Sign in with your wallet to see your balance and '
                        'activity.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('wallet-sign-in'),
                onPressed: _signingIn ? null : _signIn,
                icon: _signingIn
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
