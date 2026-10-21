import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/station_ownership_card.dart';

void main() {
  Future<void> pumpAtWidth(
    WidgetTester tester,
    double width,
    List<String> routes,
  ) async {
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [StationOwnershipCard(onNavigate: routes.add)],
          ),
        ),
      ),
    );
  }

  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('title is laid out horizontally at ${width.toInt()} dp', (
      tester,
    ) async {
      await pumpAtWidth(tester, width, []);
      final title = tester.getSize(find.text('Station ownership'));
      // The bug stacked one character per line (tall and narrow). The test
      // font draws square glyphs, so allow wrapping but require a wide title.
      expect(title.width, greaterThan(100));
      expect(title.width, greaterThan(title.height * 2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('each button navigates to its route', (tester) async {
    final routes = <String>[];
    await pumpAtWidth(tester, 360, routes);
    for (final label in ['Security', 'Transfer', 'Accept']) {
      await tester.tap(find.text(label));
    }
    expect(routes, [
      '/collect/station-security',
      '/collect/station-transfer',
      '/collect/station-accept',
    ]);
  });
}
