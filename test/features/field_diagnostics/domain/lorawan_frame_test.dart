import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/field_diagnostics/domain/lorawan_frame.dart';

void main() {
  test('parses observable fields from an unconfirmed uplink header', () {
    final frame = LoraWanFrameHeader.tryParse([
      0x40, // unconfirmed data up
      0x26, 0x01, 0x1b, 0xaa, // DevAddr, little endian on wire
      0x00, // FCtrl
      0x34, 0x12, // FCnt
    ]);

    expect(frame?.messageType, LoraWanMessageType.unconfirmedDataUp);
    expect(frame?.deviceAddress, 'aa1b0126');
    expect(frame?.frameCounter, 0x1234);
  });

  test('rejects truncated data headers instead of inventing diagnostics', () {
    expect(LoraWanFrameHeader.tryParse([0x40, 0x26, 0x01]), isNull);
  });

  test('does not present join traffic as authenticated data', () {
    final frame = LoraWanFrameHeader.tryParse([0x00]);

    expect(frame?.messageType, LoraWanMessageType.joinRequest);
    expect(frame?.deviceAddress, isNull);
    expect(frame?.frameCounter, isNull);
  });

  test('accepts copied hex with separators but rejects odd-length input', () {
    final frame = LoraWanFrameHeader.tryParseHex('40 26:01-1b aa 00 34 12');

    expect(frame?.deviceAddress, 'aa1b0126');
    expect(LoraWanFrameHeader.tryParseHex('402'), isNull);
    expect(LoraWanFrameHeader.tryParseHex('00gg'), isNull);
  });
}
