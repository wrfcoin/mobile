import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/field_diagnostics/domain/field_diagnostics_transport.dart';

void main() {
  test('exposes a runtime-separated transport seam', () {
    expect(FieldDiagnosticTransports.values.length, 4);
    expect(
      FieldDiagnosticTransports.values.where((transport) => transport.isRuntimeVerified),
      isNotEmpty,
    );
  });

  test('flags hardware transport boundaries as unverified in this session', () {
    expect(FieldDiagnosticTransports.bluetooth.isHardwareDependent, isTrue);
    expect(FieldDiagnosticTransports.flipperZero.isHardwareDependent, isTrue);
    expect(FieldDiagnosticTransports.bluetooth.isRuntimeVerified, isFalse);
  });
}

