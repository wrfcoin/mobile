import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/security/screen_security_service.dart';
import '../providers/wallet_security_provider.dart';
import '../widgets/safety_notice.dart';

/// What the user types before the words can be shown.
const String revealPhraseConfirmation = 'show my words';

/// Back up / view the recovery phrase. A cold backup: never needed to sign
/// in, unlock or send. It sits behind a plain warning, a typed confirmation
/// and the device unlock ([KeyManager.getMnemonic]).
class RecoveryPhraseScreen extends ConsumerStatefulWidget {
  const RecoveryPhraseScreen({super.key});

  @override
  ConsumerState<RecoveryPhraseScreen> createState() =>
      _RecoveryPhraseScreenState();
}

enum _Stage { warning, shown, noPhrase }

class _RecoveryPhraseScreenState extends ConsumerState<RecoveryPhraseScreen>
    with WidgetsBindingObserver {
  late final ScreenSecurityService _screenSecurity;
  final _typed = TextEditingController();
  _Stage _stage = _Stage.warning;
  List<String> _words = const [];
  bool _obscured = false;
  bool _unlocking = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _screenSecurity = ref.read(screenSecurityServiceProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _words = const [];
    _typed.dispose();
    _screenSecurity.disableProtection();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hide =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive;
    if (hide != _obscured) setState(() => _obscured = hide);
  }

  bool get _confirmed =>
      _typed.text.trim().toLowerCase() == revealPhraseConfirmation;

  Future<void> _reveal() async {
    if (!_confirmed || _unlocking) return;
    setState(() {
      _unlocking = true;
      _problem = null;
    });
    // The native flag must settle before any frame can contain the words.
    await _screenSecurity.enableProtection();
    final phrase = await ref.read(keyManagerProvider).getMnemonic();
    if (!mounted) return;
    if (phrase == null || phrase.isEmpty) {
      await _screenSecurity.disableProtection();
      setState(() {
        _unlocking = false;
        _problem = 'The phone was not unlocked. Nothing was shown.';
      });
      return;
    }
    // A private-key import stores a placeholder, not a real phrase.
    if (!bip39.validateMnemonic(phrase)) {
      await _screenSecurity.disableProtection();
      setState(() {
        _unlocking = false;
        _stage = _Stage.noPhrase;
      });
      return;
    }
    setState(() {
      _unlocking = false;
      _words = phrase.split(RegExp(r'\s+'));
      _stage = _Stage.shown;
    });
  }

  Future<void> _hide({bool backedUp = false}) async {
    setState(() {
      _words = const [];
      _typed.clear();
      _stage = _Stage.warning;
    });
    await _screenSecurity.disableProtection();
    if (backedUp) {
      await ref.read(backupConfirmedProvider.notifier).setConfirmed(true);
      if (mounted && context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery phrase')),
      body: ResponsiveCenter(
        maxContentWidth: 560,
        child: ListView(
          children: switch (_stage) {
            _Stage.warning => _warning(context),
            _Stage.shown => _shown(context),
            _Stage.noPhrase => const [
              SafetyNotice(
                key: Key('recovery-no-phrase'),
                title: 'This wallet has no recovery phrase',
                body:
                    'It was imported from a private key. Keep that key '
                    'somewhere safe; it is the only backup.',
              ),
            ],
          },
        ),
      ),
    );
  }

  List<Widget> _warning(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return [
      Text('Before you look', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      point(
        Icons.warning_amber_rounded,
        'Anyone who sees these words can take everything in this wallet.',
      ),
      point(
        Icons.support_agent,
        'Nobody from WRFCoin will ever ask for them. Not support, not a '
        'website, not an app.',
      ),
      point(
        Icons.no_photography_outlined,
        'Write them on paper. Do not take a screenshot or store them online.',
      ),
      const SafetyNotice(
        title: 'You only need them to restore',
        body:
            'Signing in, checking your balance and sending all work without '
            'them. Keep them for the day you lose this phone.',
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('recovery-confirm-field'),
        controller: _typed,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'Type "$revealPhraseConfirmation" to continue',
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('recovery-reveal'),
        onPressed: _confirmed && !_unlocking ? _reveal : null,
        icon: const Icon(Icons.fingerprint),
        label: const Text('Unlock and show words'),
      ),
      if (_problem != null) ...[
        const SizedBox(height: 12),
        Text(_problem!, style: TextStyle(color: scheme.error)),
      ],
    ];
  }

  List<Widget> _shown(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      const Text('Write these words on paper, in order.'),
      const SizedBox(height: 12),
      Container(
        key: const Key('recovery-words'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: _obscured
            ? const Text('Hidden while the app is in the background')
            : Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _words.length; i++)
                    SizedBox(
                      width: 120,
                      child: Text(
                        '${i + 1}. ${_words[i]}',
                        style: const TextStyle(
                          height: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('recovery-done'),
        onPressed: () => _hide(backedUp: true),
        child: const Text('I wrote them down'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _hide, child: const Text('Hide words')),
    ];
  }
}
