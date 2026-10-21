import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android disables app backup explicitly', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });
  test('cloud and device transfers exclude all app storage domains', () {
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    for (final kind in ['cloud-backup', 'device-transfer']) {
      final block = RegExp('<$kind>([\\s\\S]*?)</$kind>')
          .firstMatch(rules)
          ?.group(1);
      expect(block, isNotNull);
      for (final domain in [
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
        'device_root',
        'device_file',
        'device_database',
        'device_sharedpref',
      ]) {
        expect(block, contains('<exclude domain="$domain" path="." />'));
      }
    }
  });
}
