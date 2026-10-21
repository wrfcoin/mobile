enum LoraWanMessageType {
  joinRequest,
  joinAccept,
  unconfirmedDataUp,
  unconfirmedDataDown,
  confirmedDataUp,
  confirmedDataDown,
  rejoinRequest,
  proprietary,
}

/// The unencrypted LoRaWAN header information suitable for Field Mode.
///
/// This parser intentionally does not claim to authenticate, decrypt, or
/// validate a frame MIC; those operations require session keys.
class LoraWanFrameHeader {
  const LoraWanFrameHeader({
    required this.messageType,
    this.deviceAddress,
    this.frameCounter,
  });

  final LoraWanMessageType messageType;
  final String? deviceAddress;
  final int? frameCounter;

  /// Parses a copied hex frame for Field Mode. Separators are accepted, but
  /// malformed input stays absent rather than becoming fabricated telemetry.
  static LoraWanFrameHeader? tryParseHex(String input) {
    if (RegExp(r'[^0-9a-fA-F\s:,-]').hasMatch(input)) return null;
    final hex = input.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (hex.isEmpty || hex.length.isOdd) return null;
    final bytes = <int>[];
    for (var index = 0; index < hex.length; index += 2) {
      final byte = int.tryParse(hex.substring(index, index + 2), radix: 16);
      if (byte == null) return null;
      bytes.add(byte);
    }
    return tryParse(bytes);
  }

  static LoraWanFrameHeader? tryParse(List<int> bytes) {
    if (bytes.isEmpty) return null;

    final messageTypeValue = bytes.first >> 5;
    if (messageTypeValue > LoraWanMessageType.proprietary.index) return null;
    final messageType = LoraWanMessageType.values[messageTypeValue];
    if (!_isDataMessage(messageType)) {
      return LoraWanFrameHeader(messageType: messageType);
    }

    // MHDR (1) plus FHDR DevAddr (4), FCtrl (1), FCnt (2).
    if (bytes.length < 8) return null;
    final deviceAddress =
        '${_hex(bytes[4])}${_hex(bytes[3])}${_hex(bytes[2])}${_hex(bytes[1])}';
    final frameCounter = bytes[6] | (bytes[7] << 8);
    return LoraWanFrameHeader(
      messageType: messageType,
      deviceAddress: deviceAddress,
      frameCounter: frameCounter,
    );
  }

  static bool _isDataMessage(LoraWanMessageType type) => switch (type) {
    LoraWanMessageType.unconfirmedDataUp ||
    LoraWanMessageType.unconfirmedDataDown ||
    LoraWanMessageType.confirmedDataUp ||
    LoraWanMessageType.confirmedDataDown => true,
    _ => false,
  };

  static String _hex(int value) => value.toRadixString(16).padLeft(2, '0');
}
