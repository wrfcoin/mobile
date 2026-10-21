import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../domain/image_metadata_sanitizer.dart';

/// Reads a picked photo, strips its location-bearing metadata, and writes the clean bytes to a new
/// app-owned file. The clean file is the only one ever shown, classified or uploaded.
/// Throws [ImageSanitizeException] (or an I/O error) when the photo cannot be proven clean; the
/// caller must then refuse the photo (fail closed).
Future<File> sanitizePickedImage(String pickedPath, {Directory? into}) async {
  final original = await File(pickedPath).readAsBytes();
  final clean = sanitizeImageMetadata(original);
  final dir = into ?? await getTemporaryDirectory();
  final isPng = clean.length > 3 && clean[1] == 0x50;
  final file = File(
    '${dir.path}/imagery_${DateTime.now().microsecondsSinceEpoch}.${isPng ? 'png' : 'jpg'}',
  );
  await file.writeAsBytes(Uint8List.fromList(clean), flush: true);
  return file;
}
