import 'dart:convert';
import 'dart:typed_data';

const _domain = 'wrfcoin_transparent_transfer_auth_v2';

Uint8List _u32le(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

Uint8List _u64le(int value) =>
    (ByteData(8)..setUint64(0, value, Endian.little)).buffer.asUint8List();

List<int> _framed(String value) {
  final bytes = utf8.encode(value);
  return <int>[..._u32le(bytes.length), ...bytes];
}

/// Canonical bytes signed for a transparent transfer.
///
/// [amountBaseUnits] is an integer count of base units, never a WRF display
/// amount. The string fields are included byte-for-byte and are not normalized.
Uint8List transparentTransferAuthorizationMessage({
  required String chainId,
  required String networkId,
  required String from,
  required String to,
  required int amountBaseUnits,
  required int nonce,
}) {
  if (amountBaseUnits < 0 || nonce < 0) {
    throw ArgumentError('amountBaseUnits and nonce must be unsigned');
  }
  return Uint8List.fromList(<int>[
    ...utf8.encode(_domain),
    ..._framed(chainId),
    ..._framed(networkId),
    ..._framed(from),
    ..._framed(to),
    ..._u64le(amountBaseUnits),
    ..._u64le(nonce),
  ]);
}
