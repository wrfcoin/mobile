import 'package:flutter/material.dart';

import '../../domain/sdr_apt_frame_decoder.dart';

class SdrAptFrameView extends StatelessWidget {
  const SdrAptFrameView({super.key, required this.frame, this.pixelSize = 2});

  final SdrAptFrame frame;
  final double pixelSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('sdr-apt-frame-view-size'),
      width: frame.width.toDouble() * pixelSize,
      height: frame.height.toDouble() * pixelSize,
      child: CustomPaint(
        painter: _SdrAptFramePainter(frame: frame, pixelSize: pixelSize),
      ),
    );
  }
}

class _SdrAptFramePainter extends CustomPainter {
  const _SdrAptFramePainter({required this.frame, required this.pixelSize});

  final SdrAptFrame frame;
  final double pixelSize;

  @override
  void paint(Canvas canvas, Size size) {
    var index = 0;
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final pixel = frame.pixels[index++];
        final shade = Color.fromARGB(255, pixel, pixel, pixel);
        final paint = Paint()..color = shade;
        canvas.drawRect(
          Rect.fromLTWH(
            x.toDouble() * pixelSize,
            y.toDouble() * pixelSize,
            pixelSize,
            pixelSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SdrAptFramePainter oldDelegate) {
    return frame.width != oldDelegate.frame.width ||
        frame.height != oldDelegate.frame.height ||
        frame.pixels != oldDelegate.frame.pixels ||
        pixelSize != oldDelegate.pixelSize;
  }
}
