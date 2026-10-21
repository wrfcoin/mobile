import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/models/faucet_models.dart';
import '../providers/faucet_provider.dart';

/// Lets a new user obtain testnet WRF tokens by solving a math captcha.
///
/// Flow: request captcha → answer → claim. Backend rate-limit / cooldown /
/// captcha errors are surfaced verbatim; success shows the dispensed amount
/// and transaction hash. No optimistic / fake success states.
class FaucetScreen extends ConsumerStatefulWidget {
  const FaucetScreen({super.key});

  @override
  ConsumerState<FaucetScreen> createState() => _FaucetScreenState();
}

class _FaucetScreenState extends ConsumerState<FaucetScreen> {
  final _answerController = TextEditingController();

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(faucetProvider);
    final notifier = ref.read(faucetProvider.notifier);

    // Clear the stale answer whenever the challenge is dropped/refreshed.
    ref.listen<FaucetState>(faucetProvider, (prev, next) {
      if (prev?.challenge?.challengeId != next.challenge?.challengeId) {
        _answerController.clear();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Testnet Faucet')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IntroCard(),
              const SizedBox(height: 16),
              if (!state.hasWallet)
                const _NoWalletNotice()
              else ...[
                _DestinationCard(address: state.walletAddress!),
                const SizedBox(height: 16),
                if (state.result != null)
                  _SuccessCard(result: state.result!, onAgain: notifier.reset)
                else ...[
                  if (state.error != null) ...[
                    _ErrorCard(message: state.error!.message),
                    const SizedBox(height: 12),
                  ],
                  if (!state.hasChallenge)
                    _RequestChallengeButton(
                      loading: state.loadingChallenge,
                      onPressed: notifier.requestChallenge,
                    )
                  else
                    _ChallengeForm(
                      question: state.challenge!.question,
                      controller: _answerController,
                      claiming: state.claiming,
                      onSubmit: () => notifier.claim(_answerController.text),
                      onNewChallenge: notifier.requestChallenge,
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.water_drop_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'New to the testnet? Claim a one-time grant of WRF test '
                'tokens to start exploring. Solve a quick check to prove '
                "you're human. Limited to one claim per address every 24 "
                'hours.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoWalletNotice extends StatelessWidget {
  const _NoWalletNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.12),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.warning,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Create or import a wallet first — the faucet needs an '
                'address to send tokens to.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final String address;

  const _DestinationCard({required this.address});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.send_to_mobile_outlined),
        title: const Text('Tokens will be sent to'),
        subtitle: Text(
          KeyManager.maskAddress(address),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

class _RequestChallengeButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _RequestChallengeButton({
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.water_drop),
        label: Text(loading ? 'Preparing…' : 'Request Testnet Tokens'),
      ),
    );
  }
}

class _ChallengeForm extends StatelessWidget {
  final String question;
  final TextEditingController controller;
  final bool claiming;
  final VoidCallback onSubmit;
  final VoidCallback onNewChallenge;

  const _ChallengeForm({
    required this.question,
    required this.controller,
    required this.claiming,
    required this.onSubmit,
    required this.onNewChallenge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          enabled: !claiming,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Your answer',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => claiming ? null : onSubmit(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: claiming ? null : onSubmit,
            icon: claiming
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(claiming ? 'Claiming…' : 'Claim Tokens'),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: claiming ? null : onNewChallenge,
            child: const Text('New challenge'),
          ),
        ),
      ],
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final FaucetClaimResult result;
  final VoidCallback onAgain;

  const _SuccessCard({required this.result, required this.onAgain});

  @override
  Widget build(BuildContext context) {
    final amount = result.amount;
    final txHash = result.txHash;
    final balance = result.balance;

    return Card(
      color: AppColors.success.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success),
                SizedBox(width: 8),
                Text(
                  'Tokens on the way!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('Amount', '$amount WRF'),
            if (balance != null) _row('New balance', '$balance WRF'),
            _row('Tx hash', txHash, mono: true),
            const SizedBox(height: 12),
            TextButton(onPressed: onAgain, child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: mono ? 'monospace' : null,
                fontSize: mono ? 12 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.error.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
