import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_handoff.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/api/api_client.dart';
import '../providers/wallet_provider.dart';

/// The wallet-connect handoff message. A session problem offers
/// "Sign in again": the explicit user action that lifts an automatic-login
/// hold (mobile#313). "Dismiss" only hides the message; it signs nothing in.
class AuthHandoffBanner extends ConsumerStatefulWidget {
  const AuthHandoffBanner({super.key, required this.handoff});

  final AuthHandoffController handoff;

  @override
  ConsumerState<AuthHandoffBanner> createState() => _AuthHandoffBannerState();
}

class _AuthHandoffBannerState extends ConsumerState<AuthHandoffBanner> {
  bool _signingIn = false;

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    var ok = false;
    try {
      ok = await ref.read(apiClientProvider).signInNow();
    } catch (_) {
      // The client surfaces failures through the handoff message; the
      // button must never stay disabled because of one.
      ok = false;
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
    if (ok && mounted) {
      ref.invalidate(walletProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handoff = widget.handoff;
    final message = handoff.message;
    if (message == null) return const SizedBox.shrink();
    final canSignIn = handoff.offersSignIn;

    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Dismiss',
                  onPressed: handoff.clear,
                ),
              ],
            ),
            if (canSignIn)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const Key('auth-handoff-sign-in'),
                  onPressed: _signingIn ? null : _signIn,
                  icon: _signingIn
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Sign in again'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
