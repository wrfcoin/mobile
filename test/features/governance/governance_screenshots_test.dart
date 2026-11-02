import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/providers/proposals_provider.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_detail_screen.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_list_screen.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/vote_screen.dart';

import '../../test_helpers/fakes.dart';

class _EmptyProposals extends ProposalsNotifier {
  @override
  Future<List<ProposalModel>> build() async => const [];
}

// Renders with SCREENSHOT_FONTS set to Flutter's bin/cache/artifacts/material_fonts:
// flutter test --update-goldens test/features/governance/governance_screenshots_test.dart
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

  const proposal = ProposalModel(
    id: 'synthetic-1',
    title: 'Sample proposal',
    description: 'Synthetic text for this screenshot.',
    status: 'active',
  );

  const widths = {'phone-390': Size(390, 844), 'desktop-1280': Size(1280, 800)};
  for (final MapEntry(key: name, value: size) in widths.entries) {
    testWidgets('$name screenshots', (tester) async {
      await load('Roboto', 'Roboto-Regular.ttf');
      await load('MaterialIcons', 'MaterialIcons-Regular.otf');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app(Widget home) => ProviderScope(
        key: UniqueKey(),
        overrides: [
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(),
          ),
          proposalsProvider.overrideWith(_EmptyProposals.new),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme.copyWith(
            textTheme: AppTheme.darkTheme.textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'Roboto'),
            child: home,
          ),
        ),
      );
      final screens = {
        'list': const ProposalListScreen(),
        'detail': const ProposalDetailScreen(proposal: proposal),
        'vote': const VoteScreen(proposal: proposal),
      };
      for (final MapEntry(key: screen, value: widget) in screens.entries) {
        await tester.pumpWidget(app(widget));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../docs/screens/governance/$screen-$name.png',
          ),
        );
      }
    }, skip: fonts == null);
  }
}
