import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/crypto/key_manager.dart';
import '../../../services/crypto/station_signing.dart';
import '../data/station_calibration.dart';
import 'station_calibration_card.dart';

/// This phone's own station id, or null without a wallet.
final phoneStationIdProvider = FutureProvider.autoDispose<String?>((ref) async {
  final address = await ref.watch(keyManagerProvider).getAddress();
  final clean = address?.trim().toLowerCase();
  return clean == null || clean.isEmpty ? null : deriveMobileStationId(clean);
});

/// Look up any station's calibration by its public alias (default: this
/// phone's own station). Anyone can check any station: it is public data.
class StationCalibrationScreen extends ConsumerStatefulWidget {
  const StationCalibrationScreen({super.key});

  @override
  ConsumerState<StationCalibrationScreen> createState() =>
      _StationCalibrationScreenState();
}

class _StationCalibrationScreenState
    extends ConsumerState<StationCalibrationScreen> {
  final _alias = TextEditingController();
  String? _looked;

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  void _lookUp() {
    final alias = _alias.text.trim().toLowerCase();
    if (stationAliasFormat.hasMatch(alias)) setState(() => _looked = alias);
  }

  @override
  Widget build(BuildContext context) {
    final phone = ref.watch(phoneStationIdProvider).asData?.value;
    final station = _looked ?? phone;
    return Scaffold(
      appBar: AppBar(title: const Text('Calibration certificates')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'A trusted calibrator can sign a certificate for a station. '
                'The server checks it again each time you look.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _alias,
                maxLength: 15,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _lookUp(),
                decoration: const InputDecoration(
                  labelText: 'Station alias',
                  hintText: 'st_7d29a4c1e0b8',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed:
                        stationAliasFormat.hasMatch(
                          _alias.text.trim().toLowerCase(),
                        )
                        ? _lookUp
                        : null,
                    child: const Text('Look up'),
                  ),
                  if (phone != null && _looked != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _looked = null;
                        _alias.clear();
                      }),
                      child: const Text("This phone's station"),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (station == null)
                const Text(
                  'Enter a station alias to check its calibration.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else ...[
                Text(
                  _looked == null
                      ? "This phone's station: ${calibrationAliasFor(station)}"
                      : 'Station $station',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                StationCalibrationCard(stationId: station),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
