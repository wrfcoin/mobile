import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_submit_token_store.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_submit_token_screen.dart';
import 'package:wrfcoin_mobile/services/security/screen_security_service.dart';

import '../../../test_helpers/fakes.dart';

void main() {
  final station = 'mob-${'a' * 32}';
  final token = 'c' * 64;
  final packet = jsonEncode({'stationId': station, 'token': token});

  testWidgets(
    'private import is obscured, bound, cleared and never claims server matching',
    (t) async {
      final store = StationSubmitTokenStore(storage: InMemoryKeyValueStorage());
      final screen = FakeScreenSecurityClient();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            stationSubmitTokenStoreProvider.overrideWithValue(store),
            screenSecurityClientProvider.overrideWithValue(screen),
          ],
          child: MaterialApp(
            home: StationSubmitTokenScreen(stationId: station),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(screen.protectionEnabled, isTrue);
      expect(t.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      await t.enterText(find.byType(TextField), packet);
      await t.tap(find.text('Save credential'));
      await t.pumpAndSettle();
      expect(await store.read(station), token);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      expect(
        find.textContaining('Server matching is not verified'),
        findsOneWidget,
      );
      await t.tap(find.text('Remove credential'));
      await t.pumpAndSettle();
      expect(await store.read(station), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(screen.protectionEnabled, isFalse);
    },
  );

  testWidgets(
    'wrong-station packet refuses and clears input without echoing it',
    (t) async {
      final store = StationSubmitTokenStore(storage: InMemoryKeyValueStorage());
      await t.pumpWidget(
        ProviderScope(
          overrides: [stationSubmitTokenStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            home: StationSubmitTokenScreen(stationId: station),
          ),
        ),
      );
      await t.enterText(
        find.byType(TextField),
        jsonEncode({'stationId': 'mob-${'b' * 32}', 'token': token}),
      );
      await t.tap(find.text('Save credential'));
      await t.pumpAndSettle();
      expect(await store.read(station), isNull);
      expect(
        find.textContaining('Credential could not be saved'),
        findsOneWidget,
      );
      expect(
        t.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      expect(find.text(token), findsNothing);
    },
  );
}
