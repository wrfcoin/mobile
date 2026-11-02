import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/wallet_model.dart';
import '../../data/repositories/wallet_repository_impl.dart';
import '../../domain/recipient_safety.dart';

/// The web page that creates a passkey wallet, and signs and sends for it.
final Uri passkeyWalletPage = Uri.parse('https://wrfcoin.com/wallet/passkey');

/// Opens [passkeyWalletPage] in a browser tab inside the app, or failing that in
/// the browser itself. The page signs and submits on its own: nothing secret
/// comes back to the app, and the app never holds a passkey.
class PasskeyBrowser {
  const PasskeyBrowser({this.launch = launchUrl});

  /// [launchUrl], replaced in tests.
  final Future<bool> Function(Uri url, {LaunchMode mode}) launch;

  /// False when nothing on the phone could open the page.
  Future<bool> open() async {
    for (final mode in const [
      LaunchMode.inAppBrowserView,
      LaunchMode.externalApplication,
    ]) {
      try {
        if (await launch(passkeyWalletPage, mode: mode)) return true;
      } catch (error) {
        debugPrint('Passkey page did not open (${mode.name}): $error');
      }
    }
    return false;
  }
}

final passkeyBrowserProvider = Provider<PasskeyBrowser>(
  (ref) => const PasskeyBrowser(),
);

/// The passkey wallet address the user pasted into this app, or null.
///
/// It is public data, kept only so the app can read the balance. The app can't
/// tell whether the address is really the user's, and having one here signs
/// nobody in and unlocks nothing.
final passkeyAddressProvider =
    AsyncNotifierProvider<PasskeyAddressNotifier, String?>(
      PasskeyAddressNotifier.new,
    );

class PasskeyAddressNotifier extends AsyncNotifier<String?> {
  static const storageKey = 'passkey_wallet.address';

  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    return saved != null && isSendableAddress(saved) ? saved : null;
  }

  /// Throws [ArgumentError] for anything but a chain address.
  Future<void> save(String address) async {
    if (!isSendableAddress(address)) {
      throw ArgumentError('Not a wallet address');
    }
    final normalized = address.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, normalized);
    state = AsyncData(normalized);
  }

  Future<void> remove() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    state = const AsyncData(null);
  }
}

/// The public balance of a passkey wallet. No sign-in is involved.
final passkeyBalanceProvider = FutureProvider.autoDispose
    .family<WalletModel, String>((ref, address) async {
      final result = await ref
          .read(walletRepositoryProvider)
          .getWallet(address);
      return result.fold((failure) => throw failure, (wallet) => wallet);
    });
