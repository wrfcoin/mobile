import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/crypto/station_signing.dart';
import '../../data/services/station_registrar_service.dart';
import '../providers/station_registrar_provider.dart';

/// "Ask the network to register this station" for a phone station that the
/// backend holds but the chain does not have yet. Renders nothing unless the
/// network reports `station_registrar_key` active and the registrar answers.
class StationRegistrarCard extends ConsumerStatefulWidget {
  const StationRegistrarCard({super.key, required this.ownerAddress});

  final String ownerAddress;

  @override
  ConsumerState<StationRegistrarCard> createState() =>
      _StationRegistrarCardState();
}

class _StationRegistrarCardState extends ConsumerState<StationRegistrarCard> {
  bool _sending = false;
  String? _error;

  String? get _stationId {
    try {
      return deriveMobileStationId(widget.ownerAddress.trim().toLowerCase());
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _request(String stationId) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    StationSigningSession? session;
    try {
      try {
        session = await ref.read(stationRegistrarSessionOpenerProvider)();
      } on StationSigningUnavailable {
        throw const RegistrarRequestException(RegistrarRefusal.cancelled);
      } on StationSigningForegroundRequired {
        throw const RegistrarRequestException(RegistrarRefusal.cancelled);
      }
      if (session == null) {
        throw const RegistrarRequestException(RegistrarRefusal.cancelled);
      }
      if (session.stationId != stationId) {
        throw const RegistrarRequestException(RegistrarRefusal.notEligible);
      }
      await ref.read(stationRegistrarServiceProvider).request(session);
      if (!mounted) return;
      ref.invalidate(stationRegistrarStatusProvider(stationId));
    } on RegistrarRequestException catch (error) {
      if (mounted) setState(() => _error = error.refusal.userMessage);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Nothing was sent.');
      }
    } finally {
      session?.close();
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationId = _stationId;
    if (stationId == null) return const SizedBox.shrink();
    final status = ref.watch(stationRegistrarStatusProvider(stationId));
    final value = status.asData?.value;
    if (value == null) return const SizedBox.shrink();
    final releaseAt = value.releaseAt?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        key: const Key('station-registrar-card'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Register this station now',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(value.message),
              if (value.state == RegistrarState.held && releaseAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Signed after ${MaterialLocalizations.of(context).formatMediumDate(releaseAt)}, '
                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(releaseAt))}.',
                  key: const Key('station-registrar-release'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('station-registrar-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (value.state == RegistrarState.notRequested) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('station-registrar-request'),
                  onPressed: _sending ? null : () => _request(stationId),
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.how_to_reg_outlined),
                  label: const Text('Ask to register'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
