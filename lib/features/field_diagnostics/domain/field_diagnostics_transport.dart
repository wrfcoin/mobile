enum FieldTransportRuntimeState {
  implemented,
  hardwareRequired,
  notImplemented,
}

class FieldDiagnosticTransport {
  const FieldDiagnosticTransport({
    required this.id,
    required this.name,
    required this.runtimeState,
    required this.supportsAuthenticatedCapture,
    required this.runtimeBoundary,
    this.description = '',
  });

  final String id;
  final String name;
  final FieldTransportRuntimeState runtimeState;
  final bool supportsAuthenticatedCapture;
  final String runtimeBoundary;
  final String description;

  bool get isRuntimeVerified =>
      runtimeState == FieldTransportRuntimeState.implemented;

  bool get isHardwareDependent =>
      runtimeState == FieldTransportRuntimeState.hardwareRequired;
}

class FieldDiagnosticTransports {
  const FieldDiagnosticTransports._();

  static const manual = FieldDiagnosticTransport(
    id: 'manual',
    name: 'Manual paste (for field diagnostics)',
    runtimeState: FieldTransportRuntimeState.implemented,
    supportsAuthenticatedCapture: true,
    runtimeBoundary: 'Implemented in-app parser only; no live radio transport.',
    description: 'Paste a copied LoRaWAN payload and optional signature.',
  );

  static const bluetooth = FieldDiagnosticTransport(
    id: 'bluetooth',
    name: 'Bluetooth LE bridge',
    runtimeState: FieldTransportRuntimeState.hardwareRequired,
    supportsAuthenticatedCapture: false,
    runtimeBoundary: 'UNVERIFIED in this session: Bluetooth runtime transport not connected.',
    description: 'Planned: authenticated live frame transport over Bluetooth from bridge hardware.',
  );

  static const flipperZero = FieldDiagnosticTransport(
    id: 'flipper',
    name: 'Flipper Zero',
    runtimeState: FieldTransportRuntimeState.hardwareRequired,
    supportsAuthenticatedCapture: false,
    runtimeBoundary:
        'UNVERIFIED in this session: Flipper runtime transport not connected.',
    description: 'Planned: authenticated frame capture and packet ingestion via Flipper transport.',
  );

  static const unavailable = FieldDiagnosticTransport(
    id: 'audio',
    name: 'Audio bridge',
    runtimeState: FieldTransportRuntimeState.notImplemented,
    supportsAuthenticatedCapture: false,
    runtimeBoundary:
        'UNVERIFIED in this session: Audio bridge path is not implemented.',
    description: 'Planned: audio decoding transport for packet capture.',
  );

  static const values = [manual, bluetooth, flipperZero, unavailable];

  static FieldDiagnosticTransport byId(String id) => values.firstWhere(
    (transport) => transport.id == id,
    orElse: () => manual,
  );
}
