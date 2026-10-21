import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../services/location/location_service.dart';
import '../providers/welcome_controller.dart';

/// First-run welcome flow (issue #159).
///
/// Three-slide intro pitching the earn-loop + trust model, with a location
/// permission pre-prompt on slide 2 (plain-language rationale shown *before*
/// the OS dialog to lift grant rates) and wallet-creation / import CTAs plus
/// an optional referral-code field on slide 3.  Persists `seen_welcome` via
/// [WelcomeController] once the user completes or skips the flow; the router
/// uses that flag to decide whether to redirect `/` → `/welcome` on launch.
///
/// Gated by [FeatureFlags.enableFirstRunWelcome] at the router layer; this
/// widget itself is unconditional, so it renders correctly in widget tests
/// that pump it directly.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _locationRequested = false;
  bool? _locationGranted;
  final TextEditingController _referralController = TextEditingController();

  static const int _totalSlides = 3;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _requestLocation() async {
    final service = ref.read(locationServiceProvider);
    final granted = await service.requestPermission();
    if (!mounted) return;
    setState(() {
      _locationRequested = true;
      _locationGranted = granted;
    });
  }

  Future<void> _finish() async {
    await ref.read(welcomeControllerProvider.notifier).complete();
    if (!mounted) return;
    // Router redirect handles navigation back to /weather once seenWelcome flips.
    context.go('/weather');
  }

  Future<void> _createWallet() async {
    await ref.read(welcomeControllerProvider.notifier).complete();
    if (!mounted) return;
    context.go('/wallet/create');
  }

  Future<void> _importWallet() async {
    await ref.read(welcomeControllerProvider.notifier).complete();
    if (!mounted) return;
    context.go('/wallet/import');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _EarnSlide(),
                  _SensorSlide(
                    locationRequested: _locationRequested,
                    locationGranted: _locationGranted,
                    onRequestLocation: _requestLocation,
                  ),
                  _WalletSlide(
                    referralController: _referralController,
                    onCreateWallet: _createWallet,
                    onImportWallet: _importWallet,
                  ),
                ],
              ),
            ),
            _PageIndicator(currentPage: _currentPage, totalPages: _totalSlides),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  TextButton(onPressed: _finish, child: const Text('Skip')),
                  const Spacer(),
                  if (_currentPage < _totalSlides - 1)
                    FilledButton(
                      onPressed: () => _goToPage(_currentPage + 1),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                      ),
                      child: const Text('Next'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EarnSlide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const _SlidePanel(
      icon: Icons.savings_outlined,
      title: 'Earn WRF for your local weather data',
      body:
          'Your phone already has the sensors forecasters need. '
          "Every reading you contribute improves the region's forecast accuracy "
          'and earns you WRF — no mining rig, no data centre, just your phone.',
    );
  }
}

class _SensorSlide extends StatelessWidget {
  final bool locationRequested;
  final bool? locationGranted;
  final VoidCallback onRequestLocation;

  const _SensorSlide({
    required this.locationRequested,
    required this.locationGranted,
    required this.onRequestLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sensors_outlined,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          const Text(
            "Your phone's barometer is already a sensor",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'WRFCoin samples barometric pressure from the chip on your '
            'mainboard. We only need one extra thing: rough location so '
            "your readings can be grouped with your neighbours'.",
            style: TextStyle(fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (!locationRequested)
            FilledButton.icon(
              onPressed: onRequestLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Allow approximate location'),
            )
          else if (locationGranted == true)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Location access granted'),
              ],
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        "No worries — you can grant later in settings.",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onRequestLocation,
                  child: const Text('Try again'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WalletSlide extends StatelessWidget {
  final TextEditingController referralController;
  final VoidCallback onCreateWallet;
  final VoidCallback onImportWallet;

  const _WalletSlide({
    required this.referralController,
    required this.onCreateWallet,
    required this.onImportWallet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so the slide works on small-height viewports and landscape.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          const Text(
            'Your wallet stays on your device',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Your keys never leave your phone. Create a new wallet in a '
            'few taps, or import one you already have.',
            style: TextStyle(fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: referralController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Referral code (optional)',
              hintText: 'e.g. WRF-1234',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCreateWallet,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create a new wallet'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onImportWallet,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import an existing wallet'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlidePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _SlidePanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96, color: theme.colorScheme.primary),
          const SizedBox(height: 32),
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final int currentPage;
  final int totalPages;

  const _PageIndicator({required this.currentPage, required this.totalPages});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalPages, (index) {
        final active = index == currentPage;
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        );
      }),
    );
  }
}
