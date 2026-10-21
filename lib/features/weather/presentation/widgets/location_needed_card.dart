import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;

import '../../../../core/theme/app_theme.dart';
import '../../../../services/location/location_service.dart';
import '../../data/weather_location_resolver.dart';

/// Shown instead of a forecast when the weather screens have no location.
/// No request was made and no values are shown.
///
/// Each [reason] has its own message and action (mobile#327, mobile#328):
/// - permission missing: "Allow location" asks for permission on this
///   explicit tap and reloads on a grant. When Android will no longer ask,
///   it opens the app's settings instead and says why;
/// - location services off: "Turn on Location" opens the location settings;
/// - no fix: "Retry".
class LocationNeededCard extends ConsumerStatefulWidget {
  static const message = 'Allow location to see your local forecast';
  static const allowButton = 'Allow location';
  static const openSettingsButton = 'Open settings';
  static const blockedExplanation =
      "Location is off for WRFCoin and Android won't ask again. In Settings, "
      'open Permissions → Location and allow it while using the app, then '
      'come back.';
  static const servicesOffMessage =
      'Turn on Location to see your local forecast';
  static const servicesOffButton = 'Turn on Location';
  static const noFixMessage = "Couldn't get a location fix";
  static const retryButton = 'Retry';

  const LocationNeededCard({super.key, required this.reason, this.onRetry});

  final LocationUnavailableReason reason;

  /// Reloads the screen. Called after a grant, and by "Retry".
  final VoidCallback? onRetry;

  @override
  ConsumerState<LocationNeededCard> createState() => _LocationNeededCardState();
}

class _LocationNeededCardState extends ConsumerState<LocationNeededCard> {
  late bool _blocked;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _blocked = widget.reason == LocationUnavailableReason.permissionBlocked;
  }

  @override
  void didUpdateWidget(LocationNeededCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reason != widget.reason) {
      _blocked = widget.reason == LocationUnavailableReason.permissionBlocked;
    }
  }

  /// The tap is the consent: only here is the permission dialog shown.
  Future<void> _allowLocation() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(locationServiceProvider);
      final before = await service.checkPermission();
      if (before == LocationPermission.deniedForever) {
        // Android won't show the dialog: only the settings page can grant.
        await service.openAppSettings();
        if (mounted) setState(() => _blocked = true);
        return;
      }
      if (before == LocationPermission.whileInUse ||
          before == LocationPermission.always ||
          await service.requestPermission()) {
        widget.onRetry?.call();
        return;
      }
      final after = await service.checkPermission();
      if (mounted && after == LocationPermission.deniedForever) {
        setState(() => _blocked = true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOnLocation() async {
    await ref.read(locationServiceProvider).openLocationSettings();
  }

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail, actions) = switch (widget.reason) {
      LocationUnavailableReason.permissionDenied ||
      LocationUnavailableReason.permissionBlocked => (
        Icons.location_off,
        LocationNeededCard.message,
        _blocked ? LocationNeededCard.blockedExplanation : null,
        [
          FilledButton.icon(
            onPressed: _busy ? null : _allowLocation,
            icon: Icon(_blocked ? Icons.settings : Icons.my_location),
            label: Text(
              _blocked
                  ? LocationNeededCard.openSettingsButton
                  : LocationNeededCard.allowButton,
            ),
          ),
        ],
      ),
      LocationUnavailableReason.servicesOff => (
        Icons.location_disabled,
        LocationNeededCard.servicesOffMessage,
        'Location is turned off on this device.',
        [
          FilledButton.icon(
            onPressed: _turnOnLocation,
            icon: const Icon(Icons.settings),
            label: const Text(LocationNeededCard.servicesOffButton),
          ),
          TextButton(
            onPressed: widget.onRetry,
            child: const Text(LocationNeededCard.retryButton),
          ),
        ],
      ),
      LocationUnavailableReason.noFix => (
        Icons.location_searching,
        LocationNeededCard.noFixMessage,
        'Location is on, but the phone has no position yet. Try again in a '
            'moment.',
        [
          FilledButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text(LocationNeededCard.retryButton),
          ),
        ],
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
          const SizedBox(height: 8),
          const Text(
            'Only a rounded position (about 11 km) is used.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
