import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/widgets/proposal_card.dart';

// Renders with SCREENSHOT_FONTS set to Flutter's bin/cache/artifacts/material_fonts:
// flutter test --update-goldens test/core/theme/light_mode_screenshots_test.dart
// The proposal is a synthetic fixture.
void main() {
  final fonts = Platform.environment['SCREENSHOT_FONTS'];

  Future<void> load(String family, String file) async {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(
          ByteData.sublistView(File('$fonts/$file').readAsBytesSync()),
        ),
      );
    await loader.load();
  }

  testWidgets('a proposal card on the light theme', (tester) async {
    await load('Roboto', 'Roboto-Regular.ttf');
    await load('MaterialIcons', 'MaterialIcons-Regular.otf');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme.copyWith(
          textTheme: AppTheme.lightTheme.textTheme.apply(fontFamily: 'Roboto'),
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Governance')),
          body: const Padding(
            padding: EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ProposalCard(
                proposal: ProposalModel(
                  id: 'synthetic-1',
                  title: 'Sample proposal',
                  description: 'Synthetic text for this screenshot.',
                  status: 'active',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../../docs/screens/light_mode/govern-phone-390.png',
      ),
    );
  }, skip: fonts == null);
}
