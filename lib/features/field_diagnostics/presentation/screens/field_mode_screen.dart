import 'package:flutter/material.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/field_diagnostics_transport.dart';
import '../../domain/field_mode_parser.dart';

class FieldModeScreen extends StatefulWidget {
  const FieldModeScreen({super.key});

  @override
  State<FieldModeScreen> createState() => _FieldModeScreenState();
}

class _FieldModeScreenState extends State<FieldModeScreen> {
  final _payloadController = TextEditingController();
  final _signatureController = TextEditingController();
  final _sharedSecretController = TextEditingController();
  FieldDiagnosticTransport _selectedTransport =
      FieldDiagnosticTransports.manual;
  FieldModeCaptureResult? _lastResult;

  @override
  void dispose() {
    _payloadController.dispose();
    _signatureController.dispose();
    _sharedSecretController.dispose();
    super.dispose();
  }

  void _runParse() {
    final frameHex = _payloadController.text.trim();
    if (frameHex.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paste a LoRaWAN payload hex frame first.'),
        ),
      );
      return;
    }

    final result = FieldModeCaptureParser.parse(
      transport: _selectedTransport,
      frameHex: frameHex,
      signatureHex: _signatureController.text.trim(),
      sharedSecret: _sharedSecretController.text.trim(),
    );

    setState(() {
      _lastResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Field Mode')),
      body: ResponsiveListView(
        maxContentWidth: 1000,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Field transport seam',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final transport in FieldDiagnosticTransports.values)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        transport.isRuntimeVerified
                            ? Icons.check_circle_outline
                            : Icons.warning_amber,
                        color: transport.isRuntimeVerified
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      title: Text(transport.name),
                      subtitle: Text(
                        '${transport.runtimeBoundary}${transport.isRuntimeVerified ? '' : ' ${transport.isHardwareDependent ? '(UNVERIFIED)' : '(UNIMPLEMENTED)'}'}',
                      ),
                      trailing: Text(
                        transport.isRuntimeVerified ? 'available' : 'blocked',
                        style: TextStyle(
                          color: transport.isRuntimeVerified
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manual capture parsing',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<FieldDiagnosticTransport>(
                    initialValue: _selectedTransport,
                    items: [
                      for (final transport in FieldDiagnosticTransports.values)
                        DropdownMenuItem(
                          value: transport,
                          child: Text(transport.name),
                        ),
                    ],
                    onChanged: (transport) {
                      if (transport == null) {
                        return;
                      }
                      setState(() {
                        _selectedTransport = transport;
                        _signatureController.clear();
                        _sharedSecretController.clear();
                        _lastResult = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _payloadController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'LoRaWAN frame (hex, separators ok)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _signatureController,
                    decoration: const InputDecoration(
                      labelText: 'Frame signature (optional)',
                      border: OutlineInputBorder(),
                      helperText: 'Hex HMAC-SHA256 over normalized frame payload; optional when manual diagnostics is enough.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sharedSecretController,
                    decoration: const InputDecoration(
                      labelText: 'Shared secret (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _runParse,
                        icon: const Icon(Icons.playlist_add_check),
                        label: const Text('Parse & verify'),
                      ),
                      if (_selectedTransport.isHardwareDependent)
                        FilledButton.tonalIcon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'No live ${_selectedTransport.name} test in this session; using parser-only path.',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.settings_remote),
                          label: const Text('Runtime not verified'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_lastResult != null) ...[
            _ParsedCaptureCard(result: _lastResult!),
          ],
        ],
      ),
    );
  }
}

class _ParsedCaptureCard extends StatelessWidget {
  const _ParsedCaptureCard({required this.result});

  final FieldModeCaptureResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Parsed diagnostics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _SummaryLine(label: 'Transport', value: result.transportName),
            _SummaryLine(
              label: 'Frame header parsed',
              value: result.hasFrame ? 'yes' : 'no',
            ),
            _SummaryLine(
              label: 'Message type',
              value: result.frameHeader?.messageType.name ?? 'N/A',
            ),
            _SummaryLine(
              label: 'Device Address',
              value: result.frameHeader?.deviceAddress ?? 'N/A',
            ),
            _SummaryLine(
              label: 'Frame counter',
              value: result.frameHeader?.frameCounter?.toString() ?? 'N/A',
            ),
            _SummaryLine(label: 'Auth state', value: result.authState.name),
            _SummaryLine(
              label: 'Runtime-verified sync',
              value: result.canSyncToDiagnostics ? 'yes' : 'no',
            ),
            if (result.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                result.errorMessage!,
                style: const TextStyle(color: AppColors.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
