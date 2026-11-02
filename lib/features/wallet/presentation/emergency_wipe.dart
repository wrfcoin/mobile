import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_handoff.dart';
import '../../../core/errors/failures.dart';
import '../../../core/feature_flags/feature_flags.dart';
import '../../../core/widgets/app_snackbars.dart';
import '../../../services/crypto/collect_key_store.dart';
import '../../../services/crypto/key_manager.dart';
import '../../../services/crypto/wallet_secure_storage.dart';
import '../../collector/data/services/station_registration_service.dart';
import 'providers/pending_send_provider.dart';
import 'providers/transactions_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/wallet_security_provider.dart';

/// Asks the user to type WIPE, then erases this device's collect key, station
/// registration, wallet and session data, in that order. Nothing is erased
/// without the typed confirmation.
Future<void> confirmEmergencyWipe(BuildContext context, WidgetRef ref) async {
  final shouldWipe =
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final confirmationController = TextEditingController();
          var canConfirm = false;

          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Emergency wipe'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This will erase the collect key, weather-station registration, wallet, recovery metadata, address book, and active session data from this device.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmationController,
                      decoration: const InputDecoration(
                        labelText: 'Type WIPE to confirm',
                      ),
                      onChanged: (value) {
                        setState(() {
                          canConfirm = value.trim().toUpperCase() == 'WIPE';
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: canConfirm
                        ? () => Navigator.of(dialogContext).pop(true)
                        : null,
                    child: const Text('Wipe now'),
                  ),
                ],
              );
            },
          );
        },
      ) ??
      false;

  if (!shouldWipe) return;

  // Stop before touching wallet data if the collect namespace cannot be
  // erased. Keeping the wallet lets the user retry the failed wipe.
  try {
    await ref.read(collectKeyWiperProvider).wipe();
  } catch (_) {
    if (!context.mounted) return;
    AppSnackbars.error(
      context,
      const SecurityFailure(
        'Emergency wipe stopped: the collect key could not be erased. Wallet data was kept; try again.',
      ),
    );
    return;
  }

  try {
    final cleared = await ref
        .read(sharedPreferencesProvider)
        .remove(StationRegistrationService.registeredStationKey);
    if (!cleared) throw StateError('Registration cleanup failed');
    // Keep the address/metadata until key deletion succeeds: a failed
    // key wipe must not leave a private key without its wallet address.
    await ref.read(keyManagerProvider).deleteAll();
    await ref.read(walletSecureStorageProvider).clearWalletData();
  } catch (_) {
    if (!context.mounted) return;
    AppSnackbars.error(
      context,
      const SecurityFailure(
        'Emergency wipe incomplete: the collect key was erased, but wallet cleanup did not finish. Try again.',
      ),
    );
    return;
  }

  ref.invalidate(walletProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(backupConfirmedProvider);
  ref.invalidate(addressBookProvider);
  ref.invalidate(socialWalletProvider);
  ref.invalidate(pendingSendProvider);
  ref.read(authHandoffControllerProvider).clear();

  if (!context.mounted) return;
  AppSnackbars.success(context, 'Wallet wiped from this device');
  context.go('/wallet');
}
