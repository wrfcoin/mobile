import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_theme.dart';
import '../data/station_calibration.dart';

Color _tone(CalibrationStatus status) => switch (status) {
  CalibrationStatus.calibrated => AppColors.success,
  CalibrationStatus.expired ||
  CalibrationStatus.notTrusted => AppColors.wcagWarning,
  CalibrationStatus.revoked || CalibrationStatus.invalid => AppColors.error,
  CalibrationStatus.none => AppColors.textSecondary,
};

IconData _icon(CalibrationStatus status) => switch (status) {
  CalibrationStatus.calibrated => Icons.verified,
  CalibrationStatus.none => Icons.help_outline,
  _ => Icons.error_outline,
};

/// The small badge next to a station's name. Renders nothing until there is a
/// certificate to speak of.
class CalibrationBadge extends ConsumerWidget {
  const CalibrationBadge({super.key, required this.stationId});

  final String stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref
        .watch(stationCalibrationProvider(stationId))
        .asData
        ?.value
        .toNullable();
    if (view == null || view.status == CalibrationStatus.none) {
      return const SizedBox.shrink();
    }
    final tone = _tone(view.status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon(view.status), size: 14, color: tone),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            view.status.label,
            style: TextStyle(
              color: tone,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Sensor calibration for one station. Read-only: the status the backend
/// re-verified at read time, the certificate's details and its signed JSON.
/// "Unavailable" says so plainly and never implies "not calibrated".
class StationCalibrationCard extends ConsumerWidget {
  const StationCalibrationCard({
    super.key,
    required this.stationId,
    this.hideWhenOff = false,
  });

  final String stationId;

  /// On a page about the station, a network without the feature shows nothing.
  final bool hideWhenOff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stationCalibrationProvider(stationId));
    final result = state.asData?.value;
    if (hideWhenOff && result?.getLeft().toNullable() is NotAvailableFailure) {
      return const SizedBox.shrink();
    }
    void retry() => ref.invalidate(stationCalibrationProvider(stationId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_outlined, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sensor calibration',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.isLoading)
              const Text(
                'Checking calibration…',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else if (result == null)
              _Unavailable(onRetry: retry)
            else
              result.fold(
                (failure) => failure is NotAvailableFailure
                    ? Text(
                        failure.message,
                        style: const TextStyle(color: AppColors.textSecondary),
                      )
                    : _Unavailable(onRetry: retry),
                (view) => _Loaded(view: view),
              ),
          ],
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Calibration status is not available right now. Nothing about this "
        "station's calibration is confirmed; try again later.",
        style: TextStyle(color: AppColors.textSecondary),
      ),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
}

class _Loaded extends StatefulWidget {
  const _Loaded({required this.view});

  final StationCalibration view;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  bool _copied = false;

  static final _date = DateFormat('MMM d, y');

  String _day(DateTime value) => _date.format(value.toUtc());

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final certificate = view.certificate;
    final tone = _tone(view.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_icon(view.status), size: 20, color: tone),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                view.status.label,
                style: TextStyle(
                  color: tone,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          view.status.detail,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        if (certificate != null) ...[
          const Divider(height: 24),
          _Row('Signed by', certificate.issuerId),
          _Row(
            'Valid',
            '${_day(certificate.issuedAt)} to ${_day(certificate.expiresAt)}',
          ),
          if (certificate.revocation case final revocation?)
            _Row(
              'Revoked',
              '${_day(revocation.revokedAt)}: '
                  '${calibrationRevocationReasons[revocation.reason] ?? revocation.reason}',
            ),
          if (certificate.sensor case final sensor?) _Row('Sensor', sensor),
          if (certificate.method case final method?) _Row('Method', method),
          if (certificate.reference case final reference?)
            _Row('Reference', reference),
          if (certificate.notes case final notes?) _Row('Notes', notes),
          if (certificate.ownerAddress case final owner?)
            _Row('Issued to owner', _short(owner)),
          _Row('Certificate id', certificate.cid),
          if (view.signedCertificate != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copy,
              icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
              label: Text(_copied ? 'Copied' : 'Copy the signed certificate'),
            ),
            const SizedBox(height: 4),
            const Text(
              "Check the signature yourself against the calibrator's public "
              'key.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ')
            .convert(widget.view.signedCertificate),
      ),
    );
    if (mounted) setState(() => _copied = true);
  }

  static String _short(String address) => address.length > 14
      ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
      : address;
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}
