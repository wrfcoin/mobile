import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/wallet_model.dart';
import '../../domain/recipient_safety.dart';
import '../providers/passkey_wallet_provider.dart';
import '../providers/wallet_provider.dart';
import 'receive_screen.dart' show AddressQr;

/// A passkey wallet lives on wrfcoin.com. This screen opens that page in a
/// browser tab and, if the user wants, keeps the wallet's public address so the
/// app can show its balance. It never presents that as being signed in: the app
/// holds no key for this wallet.
class PasskeyWalletScreen extends ConsumerStatefulWidget {
  const PasskeyWalletScreen({super.key, this.continueToCollect = false});

  /// The first-run flow: offer the way on to Collect.
  final bool continueToCollect;

  @override
  ConsumerState<PasskeyWalletScreen> createState() =>
      _PasskeyWalletScreenState();
}

class _PasskeyWalletScreenState extends ConsumerState<PasskeyWalletScreen> {
  final _field = TextEditingController();
  String? _fieldError;
  bool _openFailed = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _openPage() async {
    final opened = await ref.read(passkeyBrowserProvider).open();
    if (mounted) setState(() => _openFailed = !opened);
  }

  /// The clipboard could hold anything, including a recovery phrase, so only an
  /// address is ever put on screen.
  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted) return;
    if (text != null && isSendableAddress(text)) {
      setState(() {
        _field.text = text.trim();
        _fieldError = null;
      });
    } else {
      setState(
        () => _fieldError = "The clipboard doesn't hold a wallet address.",
      );
    }
  }

  Future<void> _save() async {
    if (!isSendableAddress(_field.text)) {
      setState(() => _fieldError = 'That is not a 0x… wallet address.');
      return;
    }
    await ref.read(passkeyAddressProvider.notifier).save(_field.text);
    if (!mounted) return;
    _field.clear();
    setState(() => _fieldError = null);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(passkeyAddressProvider).asData?.value;
    final hasPhoneWallet = ref.watch(walletProvider).asData?.value != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Passkey wallet')),
      body: ResponsiveListView(
        maxContentWidth: 640,
        children: [
          if (saved == null) ...[
            const Text(
              'A passkey wallet lives on wrfcoin.com and unlocks with your '
              "phone's fingerprint or face. There is no phrase to write down, "
              'and no email or phone number.',
            ),
            const SizedBox(height: 16),
            const _Heading('1. Open it in a browser tab'),
            const SizedBox(height: 4),
            const Text(
              'Create your passkey there, or open one you made before. The page '
              'finds your wallet again only in the browser that made it.',
            ),
          ] else
            _SavedWallet(address: saved),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('passkey-open-page'),
              onPressed: _openPage,
              icon: const Icon(Icons.open_in_browser),
              label: Text(
                saved == null ? 'Open the passkey page' : 'Send or get tokens',
              ),
            ),
          ),
          if (_openFailed) ...[
            const SizedBox(height: 8),
            SelectableText(
              "Couldn't open a browser. Go to $passkeyWalletPage in any "
              'browser on this phone.',
              key: const Key('passkey-open-failed'),
              style: const TextStyle(color: AppColors.error),
            ),
          ],
          if (saved == null) ...[
            const SizedBox(height: 24),
            const _Heading('2. Bring your address back (optional)'),
            const SizedBox(height: 4),
            const Text(
              'Tap Copy address on that page, come back here and paste it. The '
              'app then shows your balance.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('passkey-address-field'),
              controller: _field,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Wallet address',
                hintText: '0x…',
                errorText: _fieldError,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('passkey-paste'),
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('passkey-save'),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const _Limits(),
          if (!hasPhoneWallet) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('passkey-add-phone-wallet'),
                onPressed: () => context.push('/wallet/create'),
                icon: const Icon(Icons.add),
                label: const Text('Create a 12-word wallet to collect'),
              ),
            ),
          ],
          if (widget.continueToCollect) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('passkey-continue'),
                onPressed: () => context.go('/collect'),
                child: const Text('Continue to Collect'),
              ),
            ),
          ],
          if (saved != null) ...[
            const SizedBox(height: 12),
            TextButton(
              key: const Key('passkey-remove'),
              onPressed: () =>
                  ref.read(passkeyAddressProvider.notifier).remove(),
              child: const Text('Remove this address from the app'),
            ),
            const Text(
              'Removing it changes nothing on the chain or in your passkey.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );
}

/// Says plainly what a passkey wallet can and can't do from this app.
class _Limits extends StatelessWidget {
  const _Limits();

  @override
  Widget build(BuildContext context) {
    return const Card(
      key: Key('passkey-limits'),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Heading('What works where'),
            SizedBox(height: 8),
            _Limit(
              Icons.open_in_browser,
              'In the browser tab: get test tokens, send and receive.',
            ),
            _Limit(
              Icons.visibility_outlined,
              'In this app: see the balance and show your address so people '
              "can pay you. The app has no key for this wallet, so it can't "
              'send or sign.',
            ),
            _Limit(
              Icons.sensors_outlined,
              'Collecting and earning on this phone need a 12-word wallet. A '
              "passkey wallet can't do it from here.",
            ),
          ],
        ),
      ),
    );
  }
}

class _Limit extends StatelessWidget {
  const _Limit(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SavedWallet extends ConsumerWidget {
  const _SavedWallet({required this.address});

  final String address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(passkeyBalanceProvider(address));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Chip(
                  key: Key('passkey-view-only'),
                  avatar: Icon(Icons.visibility_outlined, size: 16),
                  label: Text('View only'),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                IconButton(
                  key: const Key('passkey-refresh'),
                  tooltip: 'Read the balance again',
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.invalidate(passkeyBalanceProvider(address)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              balance.when(
                loading: () => 'Reading balance…',
                error: (_, _) => 'Balance unavailable',
                data: (wallet) => walletBalanceText(
                  wallet.balance,
                  wallet.balanceAvailability,
                ),
              ),
              key: const Key('passkey-balance'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SelectableText(
              address,
              key: const Key('passkey-address'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              "Pasted by you. The app can't check that this address is yours.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Center(child: AddressQr(address: address)),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                key: const Key('passkey-copy'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: address)),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy address'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
