import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';

/// The website's page for one transaction. Before the next block it says the
/// transaction is waiting (or not found yet) and looks again by itself.
Uri websiteTxPage(String hash) =>
    Uri.parse('https://wrfcoin.com/explore/tx/${Uri.encodeComponent(hash)}');

/// A sent transaction's reference that opens its page on wrfcoin.com, so
/// nobody has to paste it into Explore. Long-press still selects the text.
class TxReferenceLink extends StatelessWidget {
  const TxReferenceLink({
    super.key,
    required this.hash,
    this.launch = launchUrl,
  });

  final String hash;

  /// [launchUrl], replaced in tests.
  final Future<bool> Function(Uri url, {LaunchMode mode}) launch;

  Future<void> _open(BuildContext context) async {
    final url = websiteTxPage(hash);
    for (final mode in const [
      LaunchMode.inAppBrowserView,
      LaunchMode.externalApplication,
    ]) {
      try {
        if (await launch(url, mode: mode)) return;
      } catch (error) {
        debugPrint('Transaction page did not open (${mode.name}): $error');
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Couldn't open the transaction page.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          link: true,
          child: SelectableText(
            hash,
            key: const Key('tx-reference-link'),
            onTap: () => _open(context),
            style: const TextStyle(
              color: AppColors.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap to see it on wrfcoin.com. It can take about a minute to show '
          'in a block.',
          key: Key('tx-reference-note'),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
