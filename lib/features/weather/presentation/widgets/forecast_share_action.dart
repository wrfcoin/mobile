import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../wallet/presentation/providers/wallet_earned_provider.dart';
import '../../../social/weather_social_card.dart';
import '../../data/models/forecast_model.dart';

/// Earned-WRF figure shown on the shareable weather card (mobile#254): the
/// wallet's total earned from the public balance read, or null when unknown.
/// Kept as its own provider so tests can override it.
final forecastShareRewardsProvider = FutureProvider<String?>(
  (ref) => ref.watch(walletEarnedWrfProvider.future),
);

/// App-bar action that opens the existing [WeatherSocialCard] capture-and-share
/// flow for a forecast (mobile#254). Purely a call site: the card's
/// PNG capture + share-sheet logic is unchanged.
class ForecastShareAction extends StatelessWidget {
  const ForecastShareAction({
    super.key,
    required this.forecast,
    this.shareService,
  });

  /// Stable key so screens/tests can find the action.
  static const Key buttonKey = Key('forecast_share_action');

  final ForecastModel forecast;

  /// Injectable so tests can capture the share call instead of opening the
  /// platform share sheet.
  final WeatherSocialCardShareService? shareService;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: 'Share weather card',
      icon: const Icon(Icons.ios_share),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            _ForecastShareSheet(forecast: forecast, shareService: shareService),
      ),
    );
  }
}

class _ForecastShareSheet extends ConsumerWidget {
  const _ForecastShareSheet({required this.forecast, this.shareService});

  final ForecastModel forecast;
  final WeatherSocialCardShareService? shareService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The card remains shareable while rewards load or fail, carrying no
    // invented amount. Refreshing a previous value is also unconfirmed.
    final rewards = ref
        .watch(forecastShareRewardsProvider)
        .when<String?>(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          data: (value) => value,
          loading: () => null,
          error: (_, _) => null,
        );

    return SafeArea(
      child: Padding(
        // Narrow horizontal padding: the card is ~344 px wide and must fit a
        // 360 px phone without overflowing.
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: SingleChildScrollView(
          child: WeatherSocialCard(
            forecast: forecast,
            weatherRewards: rewards,
            shareService: shareService,
          ),
        ),
      ),
    );
  }
}
