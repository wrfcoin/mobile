import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/observability/telemetry_redactor.dart';

void main() {
  test('redacts sensitive telemetry fields recursively', () {
    final redacted = TelemetryRedactor.redactMap(<String, dynamic>{
      'walletAddress': 'wrf1234567890',
      'amount': '1.25',
      'nested': <String, dynamic>{'privateKey': 'secret', 'latitude': 37.77},
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'to': 'wrfabc'},
      ],
    });

    expect(redacted['walletAddress'], '[REDACTED]');
    expect(redacted['amount'], '1.25');
    expect(redacted['nested']['privateKey'], '[REDACTED]');
    expect(redacted['nested']['latitude'], '[REDACTED]');
    expect(redacted['items'][0]['to'], '[REDACTED]');
  });

  test('redacts sensitive string values even on non-sensitive keys', () {
    final redacted = TelemetryRedactor.redactMap(<String, dynamic>{
      'message':
          'sending from wrf1234567890abcdef to 0x1234567890abcdef1234567890abcdef12345678',
      'meta': <String, dynamic>{
        'details':
            'private key 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
      'entries': <dynamic>[
        'jwt eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.longpayloadsegment123.longsignature987',
        <String, dynamic>{'note': 'authorization: Bearer abc.def.ghi'},
      ],
    });

    expect(redacted['message'], isNot(contains('wrf1234567890abcdef')));
    expect(
      redacted['message'],
      isNot(contains('0x1234567890abcdef1234567890abcdef12345678')),
    );
    expect(redacted['message'], contains('[REDACTED]'));
    expect(redacted['meta']['details'], isNot(contains('0xaaaaaaaa')));
    expect(redacted['entries'][0], isNot(contains('eyJhbGciOiJIUzI1Ni')));
    expect(
      redacted['entries'][1]['note'],
      isNot(contains('Bearer abc.def.ghi')),
    );
  });

  test('redacts mnemonic-like phrase values', () {
    final redacted = TelemetryRedactor.redactMap(<String, dynamic>{
      'backupText':
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    });

    expect(redacted['backupText'], '[REDACTED]');
  });
}
