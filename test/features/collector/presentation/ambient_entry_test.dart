import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/pws_dashboard_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';

import '../../../test_helpers/fakes.dart';

class _Flags extends FeatureFlagsNotifier {
  _Flags(this.enabled);
  final bool enabled;
  @override
  FeatureFlags build() => FeatureFlags(enablePwsAutoDiscovery: enabled);
}

class _Wallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => null;
}

class _Transport implements HttpClientAdapter {
  _Transport(this.status);
  final int status;
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(status == 200 ? [] : {'error': 'Unavailable'}),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final status in [200, 503]) {
    for (final enabled in [false, true]) {
      testWidgets('Ambient entry flag=$enabled on station response $status', (
        tester,
      ) async {
        final transport = _Transport(status);
        final api = ApiClient(
          dio: Dio(BaseOptions(baseUrl: 'https://backend.invalid/api'))
            ..httpClientAdapter = transport,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              featureFlagsProvider.overrideWith(() => _Flags(enabled)),
              appPreferencesStoreProvider.overrideWithValue(
                TestAppPreferencesStore(),
              ),
              apiClientProvider.overrideWithValue(api),
              walletProvider.overrideWith(_Wallet.new),
            ],
            child: const MaterialApp(home: PwsDashboardScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Connect Ambient station'),
          enabled ? findsOneWidget : findsNothing,
        );
        expect(transport.paths, ['/oracle/stations']);
        expect(find.text('Scanning local network…'), findsNothing);
        expect(
          find.text('No Ecowitt or Davis stations found on this network.'),
          findsNothing,
        );
        if (enabled) {
          await tester.tap(find.byTooltip('Connect Ambient station'));
          await tester.pumpAndSettle();
          expect(
            find.text('Sign in from Wallet before connecting a station.'),
            findsOneWidget,
          );
          expect(transport.paths, ['/oracle/stations']);
        }
      });
    }
  }
}
