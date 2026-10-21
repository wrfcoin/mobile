import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sdr_apt/domain/sdr_apt_frame_decoder.dart';
import 'package:wrfcoin_mobile/features/sdr_apt/presentation/widgets/sdr_apt_frame_view.dart';

void main() {
  test('decodes legacy recorded frames from validated payloads', () {
    final sample = Uint8List.fromList([
      0x53,
      0x41,
      0x54,
      0x31,
      0x02,
      0x02,
      0,
      64,
      128,
      255,
    ]);

    final frame = const LegacySdrAptDecoder().decode(sample);

    expect(frame.width, equals(2));
    expect(frame.height, equals(2));
    expect(frame.pixels, equals(Uint8List.fromList([0, 64, 128, 255])));
  });

  test('rejects unknown frame formats and malformed lengths', () {
    // 7 bytes = 4-byte header + width(1) + height(1) + 1 payload byte, so the
    // length check passes and only the magic check can reject this sample.
    final badFormat = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x01, 0x01, 0x7F]);
    final badLength = Uint8List.fromList([
      0x53,
      0x41,
      0x54,
      0x31,
      0x02,
      0x02,
      1,
      2,
      3,
    ]);
    final decoder = const LegacySdrAptDecoder();

    expect(
      () => decoder.decode(badFormat),
      throwsA(isA<SdrAptDecodeFailure>()),
    );
    expect(
      () => decoder.decode(badLength),
      throwsA(isA<SdrAptDecodeFailure>()),
    );
  });

  test('decodes through transport + workflow seam', () async {
    final sample = Uint8List.fromList([
      0x53,
      0x41,
      0x54,
      0x31,
      0x03,
      0x01,
      12,
      24,
      48,
    ]);
    final workflow = SdrAptWorkflow(
      transport: InMemoryAptSampleTransport(sample),
      decoder: const LegacySdrAptDecoder(),
    );

    final frame = await workflow.decodeCurrent();
    expect(frame.width, equals(3));
    expect(frame.height, equals(1));
    expect(frame.pixels.last, equals(48));
  });

  testWidgets('renders a decoded frame into a sized image surface', (
    tester,
  ) async {
    final sample = Uint8List.fromList([
      0x53,
      0x41,
      0x54,
      0x31,
      0x02,
      0x01,
      4,
      9,
    ]);
    final frame = const LegacySdrAptDecoder().decode(sample);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SdrAptFrameView(frame: frame, pixelSize: 4)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('sdr-apt-frame-view-size')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('sdr-apt-frame-view-size')),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('sdr-apt-frame-view-size'))),
      const Size(8, 4),
    );
  });
}
