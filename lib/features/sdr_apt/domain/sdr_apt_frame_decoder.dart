import 'dart:typed_data';

/// In-memory representation of an APT-like decoded frame. Pixel values are
/// 0..255 grayscale samples, row-major.
class SdrAptFrame {
  const SdrAptFrame({
    required this.width,
    required this.height,
    required this.pixels,
  }) : assert(width > 0),
       assert(height > 0),
       assert(pixels.length == width * height);

  final int width;
  final int height;
  final Uint8List pixels;
}

class SdrAptDecodeFailure implements Exception {
  const SdrAptDecodeFailure(this.message);

  final String message;

  @override
  String toString() => 'SdrAptDecodeFailure: $message';
}

/// Decoder seam for recorded samples that are safe to test without device access.
abstract class SdrAptDecoder {
  SdrAptFrame decode(Uint8List sample);
}

/// Wire format used for the first shippable #90 slice:
/// [0]=0x53 'S', [1]=0x41 'A', [2]=0x54 'T', [3]=0x31 '1'
/// [4]=width (u8), [5]=height (u8), then width*height grayscale bytes.
class LegacySdrAptDecoder implements SdrAptDecoder {
  const LegacySdrAptDecoder();

  static const int _headerLength = 6;
  static const List<int> _magic = [0x53, 0x41, 0x54, 0x31];

  @override
  SdrAptFrame decode(Uint8List sample) {
    if (sample.length < _headerLength) {
      throw const SdrAptDecodeFailure('sample too short');
    }

    if (!_matchesMagic(sample.sublist(0, 4))) {
      throw const SdrAptDecodeFailure('unrecognized sample format');
    }

    final width = sample[4];
    final height = sample[5];
    if (width == 0 || height == 0) {
      throw const SdrAptDecodeFailure('invalid frame dimensions');
    }

    final expectedPixelCount = width * height;
    final expectedTotalLength = _headerLength + expectedPixelCount;
    if (sample.length != expectedTotalLength) {
      throw const SdrAptDecodeFailure('sample payload length mismatch');
    }

    return SdrAptFrame(
      width: width,
      height: height,
      pixels: Uint8List.fromList(sample.sublist(_headerLength)),
    );
  }

  bool _matchesMagic(List<int> bytes) {
    if (bytes.length != _magic.length) return false;
    for (var index = 0; index < _magic.length; index++) {
      if (bytes[index] != _magic[index]) return false;
    }
    return true;
  }
}

/// Transport seam for frame source injection in tests and production adapters.
abstract class SdrAptSampleTransport {
  Future<Uint8List> readSample();
}

class SdrAptWorkflow {
  const SdrAptWorkflow({
    required this.transport,
    this.decoder = const LegacySdrAptDecoder(),
  });

  final SdrAptSampleTransport transport;
  final SdrAptDecoder decoder;

  Future<SdrAptFrame> decodeCurrent() async {
    final sample = await transport.readSample();
    return decoder.decode(sample);
  }
}

class InMemoryAptSampleTransport implements SdrAptSampleTransport {
  const InMemoryAptSampleTransport(this.sample);

  final Uint8List sample;

  @override
  Future<Uint8List> readSample() async => sample;
}
