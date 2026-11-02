import 'dart:io';

import 'package:flutter/services.dart';

/// Phone (390 px) and desktop (1280 px) widths for PR screenshots.
const screenshotSizes = <(String, Size)>[
  ('phone-390', Size(390, 1500)),
  ('desktop-1280', Size(1280, 1150)),
];

/// Real fonts for PR screenshots, from Flutter's material_fonts cache:
///
///     SCREENSHOT_FONT_DIR=$FLUTTER/bin/cache/artifacts/material_fonts \
///       flutter test --update-goldens <screenshots test>
Future<void> loadScreenshotFonts() =>
    loadRealFonts(Platform.environment['SCREENSHOT_FONT_DIR']!);

/// The same fonts for layout tests. The default test font draws every letter
/// as a full square, about 1.8 times as wide as real text, so tab content
/// that fits on a phone reports overflow at 390 px.
Future<void> loadFlutterCacheFonts() => loadRealFonts(
  File(Platform.resolvedExecutable).parent.parent.parent.uri
      .resolve('material_fonts')
      .toFilePath(),
);

Future<void> loadRealFonts(String dir) async {
  Future<ByteData> bytes(String file) async =>
      ByteData.sublistView(File('$dir/$file').readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(bytes('Roboto-$weight.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(bytes('MaterialIcons-Regular.otf'))).load();
}
