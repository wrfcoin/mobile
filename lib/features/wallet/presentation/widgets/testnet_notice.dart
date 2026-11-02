import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feature_flags/feature_flags.dart';

const testnetNoticeText =
    'This is a test network. It may be reset without notice. Balances and tokens have no monetary value. No migration to mainnet is promised or implied. Please attach no production bridges, exchange listings or irreplaceable assets.';
const testnetDisclaimerUrl = 'https://wrfcoin.com/testnet-disclaimer.html';

/// Whether the user has closed the notice on the wallet page. Only ever set by
/// the notice's own X, so it has been on screen by then. If the preference
/// can't be read, the notice shows.
final testnetNoticeDismissedProvider =
    NotifierProvider<TestnetNoticeDismissedNotifier, bool>(
      TestnetNoticeDismissedNotifier.new,
    );

class TestnetNoticeDismissedNotifier extends Notifier<bool> {
  static const preferenceKey = 'testnet_notice.dismissed';

  @override
  bool build() {
    try {
      return ref.read(sharedPreferencesProvider).getBool(preferenceKey) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> dismiss() async {
    state = true;
    try {
      await ref.read(sharedPreferencesProvider).setBool(preferenceKey, true);
    } catch (_) {
      // Closed for now; it comes back on the next start.
    }
  }
}

/// The notice's words and link. Settings > About always shows these.
class TestnetNoticeText extends StatelessWidget {
  const TestnetNoticeText({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(testnetNoticeText, style: TextStyle(fontSize: 14)),
      SizedBox(height: 4),
      Text(testnetDisclaimerUrl, style: TextStyle(fontSize: 12)),
    ],
  );
}

class TestnetNotice extends ConsumerWidget {
  const TestnetNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(testnetNoticeDismissedProvider)) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scrolls when a large text size leaves it too little height.
            const Expanded(
              child: SingleChildScrollView(child: TestnetNoticeText()),
            ),
            IconButton(
              key: const Key('testnet-notice-dismiss'),
              tooltip: 'Dismiss testnet notice',
              icon: const Icon(Icons.close, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  ref.read(testnetNoticeDismissedProvider.notifier).dismiss(),
            ),
          ],
        ),
      ),
    );
  }
}
