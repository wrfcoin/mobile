import 'dart:typed_data';

/// Returns true if [certSha256Bytes] matches any fingerprint in [pinnedHashes].
///
/// [pinnedHashes] entries are colon-delimited uppercase hex strings
/// (e.g. "AB:CD:EF:01:..."). [certSha256Bytes] is the raw 32-byte SHA-256
/// digest of the leaf certificate's DER encoding.
bool certificateMatchesPins(
  Uint8List? certSha256Bytes,
  List<String> pinnedHashes,
) {
  if (certSha256Bytes == null || certSha256Bytes.isEmpty) return false;
  final certHex = certSha256Bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
  return pinnedHashes.any((pin) => pin.toUpperCase() == certHex);
}
