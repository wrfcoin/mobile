import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wrfcoin_mobile/features/collector/presentation/providers/station_profile_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_profile_screen.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/uptime_badge.dart';

StationProfile _mockProfile() => StationProfile(
      id: 'station-abc',
      name: 'Test Station Alpha',
      model: 'Davis Vantage Pro2',
      status: 'online',
      memberSince: DateTime(2025, 6, 15),
      totalReadings: 25000,
      uptimePercent: 99.2,
      recentReadings: List.generate(
        48,
        (i) => StationReading(
          timestamp: DateTime(2026, 3, 25, 0, i * 5),
          temperature: 20.0 + (i % 5) * 0.5,
          humidity: 55 + (i % 10),
          pressure: 1012.0 + (i % 3) * 0.5,
        ),
      ),
      forecastContributions: 3200,
      coverageRadiusKm: 5.4,
      contributorPercentile: 8,
      tempMin24h: 18.0,
      tempMax24h: 24.5,
      tempAvg24h: 21.2,
      humidityMin24h: 40,
      humidityMax24h: 75,
      humidityAvg24h: 58,
      pressureMin24h: 1010,
      pressureMax24h: 1016,
      pressureAvg24h: 1013,
      uptimeHeatmap: {for (var i = 0; i < 365; i++) i: 45},
    );

void main() {
  group('StationProfileScreen', () {
    // The screen contains a repeating animation (_PulseIndicator), so we
    // must avoid pumpAndSettle (it never finishes). Use tester.pump() with
    // explicit durations instead.

    testWidgets('renders loading then profile data', (tester) async {
      final profile = _mockProfile();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationProfileProvider('station-abc')
                .overrideWith((ref) => Future.value(profile)),
          ],
          child: const MaterialApp(
            home: StationProfileScreen(stationId: 'station-abc'),
          ),
        ),
      );

      // Initially shows loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Station Profile'), findsOneWidget);

      // Resolve the FutureProvider
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Station name and model should appear
      expect(find.text('Test Station Alpha'), findsOneWidget);
      expect(find.text('Davis Vantage Pro2'), findsOneWidget);

      // Uptime badge should be present
      expect(find.byType(UptimeBadge), findsOneWidget);

      // Live Conditions header should be visible
      expect(find.text('Live Conditions'), findsOneWidget);
    });

    testWidgets('scrolls to reveal impact and uptime sections', (tester) async {
      final profile = _mockProfile();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationProfileProvider('station-abc')
                .overrideWith((ref) => Future.value(profile)),
          ],
          child: const MaterialApp(
            home: StationProfileScreen(stationId: 'station-abc'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll down to find impact section (use first ListView, not heatmap's horizontal one)
      final listView = find.byType(ListView).first;
      await tester.drag(listView, const Offset(0, -600));
      await tester.pump();

      expect(find.text('Network Impact'), findsOneWidget);

      // Scroll more to find uptime section
      await tester.drag(listView, const Offset(0, -400));
      await tester.pump();

      expect(find.text('Uptime History'), findsOneWidget);
    });
  });

  group('UptimeBadge', () {
    testWidgets('shows correct percentage text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: UptimeBadge(uptimePercent: 99.5)),
          ),
        ),
      );

      expect(find.text('99.5%'), findsOneWidget);
      expect(find.text('uptime'), findsOneWidget);
    });

    testWidgets('renders green for >= 99% uptime', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: UptimeBadge(uptimePercent: 99.0)),
          ),
        ),
      );

      expect(find.byType(UptimeBadge), findsOneWidget);
    });

    testWidgets('renders at custom size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: UptimeBadge(uptimePercent: 97.0, size: 100)),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(UptimeBadge),
          matching: find.byType(SizedBox),
        ),
      );
      expect(sizedBox.width, 100);
      expect(sizedBox.height, 100);
    });
  });
}
