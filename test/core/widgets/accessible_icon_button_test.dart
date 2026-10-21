import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/widgets/accessible_icon_button.dart';

void main() {
  group('AccessibleIconButton', () {
    testWidgets('renders at least 48x48 logical pixels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AccessibleIconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {},
                tooltip: 'Open settings',
              ),
            ),
          ),
        ),
      );

      final box = tester.renderObject<RenderBox>(
        find.byType(AccessibleIconButton),
      );
      expect(box.size.width, greaterThanOrEqualTo(48.0));
      expect(box.size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('Semantics label is the tooltip by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleIconButton(
              icon: const Icon(Icons.close),
              onPressed: () {},
              tooltip: 'Close panel',
            ),
          ),
        ),
      );

      final semanticsNode = tester.getSemantics(find.byType(AccessibleIconButton));
      expect(semanticsNode.label, 'Close panel');
    });

    testWidgets('Semantics label uses semanticsLabel override when provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleIconButton(
              icon: const Icon(Icons.close),
              onPressed: () {},
              tooltip: 'X',
              semanticsLabel: 'Close the panel',
            ),
          ),
        ),
      );

      final semanticsNode = tester.getSemantics(find.byType(AccessibleIconButton));
      expect(semanticsNode.label, 'Close the panel');
    });

    testWidgets('onPressed callback fires on tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleIconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => tapped = true,
              tooltip: 'Refresh',
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AccessibleIconButton));
      expect(tapped, isTrue);
    });
  });
}
