import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/formatting/reported_amount.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/sensor_stream_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/pws_dashboard_screen.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_list_screen.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/widgets/treasury_card.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';

import '../test_helpers/fakes.dart';

const _largeBase = '9007199254740993';
const _largeDisplay = '90071992.54740993';

Map<String, Object?> _units(String field, String encoding) => {
  'denomination': 'WRF',
  'baseUnitDecimals': 8,
  'baseUnitsPerUnit': '100000000',
  'available': true,
  'fields': {field: encoding},
};

// Exact backend#1430 treasury contract, including misleading legacy balances.
const _unknownTreasury = {
  'denomination': null,
  'baseUnitDecimals': null,
  'baseUnitsPerUnit': null,
  'available': false,
  'reason': 'treasury_units_not_established',
  'fields': {
    'balance': 'unknown',
    'totalDeposits': 'unknown',
    'totalWithdrawals': 'unknown',
  },
};

void _expectUnavailable(String text, Object? amount) {
  expect(find.text(text), findsOneWidget);
  expect(find.textContaining('WRF'), findsNothing);
  expect(find.textContaining('credits'), findsNothing);
  if (amount is String) expect(find.text(amount), findsNothing);
}

Future<void> _pumpTreasury(
  WidgetTester tester,
  Map<String, Object?> treasury,
) async {
  final calls = <String>[];
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls.add(options.path);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: options.path == ApiConstants.proposals
                  ? {'proposals': []}
                  : {'success': true, 'data': treasury},
            ),
          );
        },
      ),
    );
  addTearDown(() => dio.close(force: true));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        governanceRepositoryProvider.overrideWithValue(
          GovernanceRepository(dio),
        ),
      ],
      child: const MaterialApp(home: ProposalListScreen()),
    ),
  );
  await tester.pumpAndSettle();
  expect(calls, containsAll([ApiConstants.treasury, ApiConstants.proposals]));
  expect(tester.takeException(), isNull);
}

Future<void> _pumpPws(WidgetTester tester, Map<String, Object?> station) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final calls = <String>[];
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls.add(options.path);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': [
                  {
                    'id': 'st_synthetic',
                    'name': 'Fixture station',
                    'status': 'offline',
                    ...station,
                  },
                ],
              },
            ),
          );
        },
      ),
    );
  addTearDown(() => dio.close(force: true));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appPreferencesStoreProvider.overrideWithValue(
          TestAppPreferencesStore(const AppPreferences()),
        ),
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        sensorStreamProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: const MaterialApp(home: PwsDashboardScreen()),
    ),
  );
  // The sensor loading indicator can keep animating. Await the completed
  // station response/render instead of waiting for all screen animations.
  for (
    var i = 0;
    i < 20 && find.text('Fixture station').evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(calls, [ApiConstants.oracleStations]);
  expect(find.text('Fixture station'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  test('actual station earnings field metadata converts exactly', () {
    final units = {
      ..._units('totals.rewardedBaseUnits', 'base_units'),
      'fields': {
        'earnings[].amountBaseUnits': 'base_units',
        'earnings[].amountWrf': 'display_units',
        'totals.rewardedBaseUnits': 'base_units',
        'totals.rewardedWrf': 'display_units',
      },
    };
    expect(
      declaredWrfAmount(_largeBase, units, 'totals.rewardedBaseUnits'),
      '$_largeDisplay WRF',
    );
    expect(
      declaredWrfAmount(_largeDisplay, units, 'totals.rewardedWrf'),
      '$_largeDisplay WRF',
    );
    expect(declaredWrfAmount(_largeBase, units, 'earnings'), isNull);
    expect(
      declaredWrfAmount(_largeBase, {
        ...units,
        'available': false,
      }, 'totals.rewardedBaseUnits'),
      isNull,
    );
  });
  for (final value in [
    null,
    false,
    9007199254740992,
    1.5,
    '1e8',
    'NaN',
    '-1',
    '1.123456789',
  ]) {
    test('display_units refuses malformed or imprecise wire amount $value', () {
      expect(
        declaredWrfAmount(value, _units('balance', 'display_units'), 'balance'),
        isNull,
      );
    });
  }
  for (final amount in [_largeDisplay, '150000000.00000000', '0.00000000']) {
    testWidgets('backend unknown treasury hides legacy amount $amount', (
      tester,
    ) async {
      await _pumpTreasury(tester, {
        'balance': amount,
        'currency': 'WRF', // Legacy currency cannot override amountUnits.
        'amountUnits': _unknownTreasury,
      });
      _expectUnavailable('Balance unavailable', amount);
    });
    testWidgets('treasury absent metadata hides legacy amount $amount', (
      tester,
    ) async {
      await _pumpTreasury(tester, {'balance': amount, 'currency': 'WRF'});
      _expectUnavailable('Balance unavailable', amount);
    });
  }

  for (final (amount, encoding, expected) in [
    (_largeBase, 'base_units', _largeDisplay),
    (_largeDisplay, 'display_units', _largeDisplay),
    ('0', 'base_units', '0'),
  ]) {
    testWidgets('treasury $encoding $amount uses declared units exactly', (
      tester,
    ) async {
      await _pumpTreasury(tester, {
        'balance': amount,
        'amountUnits': _units('balance', encoding),
      });
      expect(find.text('$expected WRF'), findsOneWidget);
      expect(find.textContaining('Unit not reported'), findsNothing);
    });
    testWidgets('PWS $encoding $amount uses only its own earnings metadata', (
      tester,
    ) async {
      await _pumpPws(tester, {
        'earnings': amount,
        'amountUnits': _units('earnings', encoding),
      });
      expect(find.text('$expected WRF earned'), findsOneWidget);
    });
  }

  for (final (name, override) in <(String, Map<String, Object?>)>[
    ('unavailable', {'available': false}),
    ('missing availability', {'available': null}),
    ('string availability', {'available': 'true'}),
    ('unknown denomination', {'denomination': null}),
    ('other denomination', {'denomination': 'OTHER'}),
    ('wrong decimals', {'baseUnitDecimals': 9}),
    ('string decimals', {'baseUnitDecimals': '8'}),
    ('missing decimals', {'baseUnitDecimals': null}),
    ('wrong ratio', {'baseUnitsPerUnit': '1000'}),
    ('missing ratio', {'baseUnitsPerUnit': null}),
    (
      'unknown encoding',
      {
        'fields': {'balance': 'unknown'},
      },
    ),
    (
      'wrong field',
      {
        'fields': {'totals.rewardedBaseUnits': 'base_units'},
      },
    ),
    ('missing fields', {'fields': null}),
  ]) {
    testWidgets('treasury $name refuses a WRF-looking number', (tester) async {
      await _pumpTreasury(tester, {
        'balance': _largeBase,
        'amountUnits': {..._units('balance', 'base_units'), ...override},
      });
      _expectUnavailable('Balance unavailable', _largeBase);
    });
  }

  for (final amount in [null, 'NaN', '150000000 WRF', '-1', false, 1.5]) {
    testWidgets('declared treasury cannot manufacture amount $amount', (
      tester,
    ) async {
      await _pumpTreasury(tester, {
        'balance': amount,
        'amountUnits': _units('balance', 'base_units'),
      });
      _expectUnavailable('Balance unavailable', amount);
    });
  }

  for (final amount in [_largeBase, '0', null]) {
    testWidgets('bare PWS earnings $amount remain unavailable', (tester) async {
      await _pumpPws(tester, {'earnings': amount});
      _expectUnavailable('Earnings unavailable', amount);
    });
  }
  testWidgets('PWS cannot borrow the separate station earnings contract', (
    tester,
  ) async {
    await _pumpPws(tester, {
      'earnings': _largeBase,
      'amountUnits': {
        ..._units('earnings[].amountBaseUnits', 'base_units'),
        'fields': {
          'earnings[].amountBaseUnits': 'base_units',
          'earnings[].amountWrf': 'display_units',
          'totals.rewardedBaseUnits': 'base_units',
          'totals.rewardedWrf': 'display_units',
        },
      },
    });
    _expectUnavailable('Earnings unavailable', _largeBase);
  });
  testWidgets('PWS unavailable known units never manufacture a zero total', (
    tester,
  ) async {
    await _pumpPws(tester, {
      'earnings': '0',
      'amountUnits': {..._units('earnings', 'base_units'), 'available': false},
    });
    _expectUnavailable('Earnings unavailable', '0');
  });

  testWidgets('treasury card without metadata does not label caller strings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TreasuryCard(balance: _largeDisplay)),
      ),
    );
    _expectUnavailable('Balance unavailable', _largeDisplay);
  });
}
