import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/repositories/wallet_repository_impl.dart';

/// The Receive QR. Exposes the encoded [address] so tests can pin it.
class AddressQr extends StatelessWidget {
  const AddressQr({super.key, required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: address,
      version: QrVersions.auto,
      size: 200,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: AppColors.background,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: AppColors.background,
      ),
    );
  }
}

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  bool _showStealth = false;
  String? _stealthAddress;
  bool _loadingStealth = false;
  String? _stealthError;

  late final Future<({String? address, bool canonical})> _identity = _read();

  Future<({String? address, bool canonical})> _load() => _identity;

  Future<({String? address, bool canonical})> _read() async {
    final keys = ref.read(keyManagerProvider);
    final address = await keys.getAddress();
    return (address: address, canonical: await keys.canSignTransactions());
  }

  Future<void> _generateStealthAddress(String myAddress) async {
    setState(() {
      _loadingStealth = true;
      _stealthError = null;
    });
    final result = await ref
        .read(walletRepositoryProvider)
        .generateStealthAddress(myAddress);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _stealthError = failure.toString();
        _loadingStealth = false;
      }),
      (addr) => setState(() {
        _stealthAddress = addr;
        _loadingStealth = false;
      }),
    );
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Address copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: FutureBuilder<({String? address, bool canonical})>(
        future: _load(),
        builder: (context, snapshot) {
          final loaded = snapshot.data;
          if (loaded == null) {
            return snapshot.connectionState == ConnectionState.done
                ? const Center(child: Text('No wallet address found'))
                : const Center(child: CircularProgressIndicator());
          }
          final address = loaded.address;
          if (address == null) {
            return const Center(child: Text('No wallet address found'));
          }
          if (!loaded.canonical) {
            // Legacy / unmarked wallet: it can receive but cannot spend here.
            // Withhold the QR, copy and stealth controls so this address is
            // not published as a "send here" destination.
            return const _ReceiveOnlyNotice();
          }

          final displayAddress = (_showStealth && _stealthAddress != null)
              ? _stealthAddress!
              : address;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Standard'),
                    Switch(
                      value: _showStealth,
                      onChanged: (v) {
                        setState(() => _showStealth = v);
                        if (v && _stealthAddress == null) {
                          _generateStealthAddress(address);
                        }
                      },
                    ),
                    const Text('Stealth (private)'),
                  ],
                ),
                if (_showStealth) ...[
                  const SizedBox(height: 4),
                  Text(
                    'One-time address — safe to share publicly.\nSender cannot link it to your wallet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_loadingStealth)
                  const CircularProgressIndicator()
                else if (_stealthError != null && _showStealth)
                  Column(
                    children: [
                      Text(
                        'Could not generate stealth address: $_stealthError',
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => _generateStealthAddress(address),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AddressQr(address: displayAddress),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _showStealth
                        ? 'One-time stealth address'
                        : 'Your receiving ID',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SelectableText(
                      displayAddress,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _copyAddress(displayAddress),
                    icon: const Icon(Icons.copy),
                    label: Text(
                      _showStealth ? 'Copy Stealth Address' : 'Copy Address',
                    ),
                  ),
                  if (_showStealth) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _stealthAddress = null);
                        _generateStealthAddress(address);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Generate New Stealth Address'),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReceiveOnlyNotice extends StatelessWidget {
  const _ReceiveOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 40),
            SizedBox(height: 12),
            Text(
              'Receive-only wallet',
              key: Key('receive-only-notice'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'This wallet can receive but cannot spend in this app, so its '
              'address is not shown for others to send to. Import your '
              'recovery phrase to create a canonical wallet, then share that '
              'address instead.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
