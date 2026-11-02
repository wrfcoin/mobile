import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/preferences/app_preferences.dart';
import '../../../../services/location/location_service.dart';
import '../providers/welcome_controller.dart';

/// First-run welcome flow (issue #159).
///
/// Three slides: what the app does, the sensors and location it needs (asked
/// here, in plain language, before the OS dialog), and the wallet choice. A
/// wallet is the only account: no sign-up, email or phone number. Choosing one
/// carries on to Collect. Persists `seen_welcome` via [WelcomeController] once
/// the user chooses or skips; the router uses that flag to decide whether to
/// redirect to `/welcome` on launch.
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

  static const int _totalSlides = 3;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
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
    // The button says sensors and location, so a yes to the OS dialog is the
    // consent Collect asks for. A no records nothing; Privacy Center can undo it.
    if (granted) {
      final preferences = ref.read(appPreferencesProvider.notifier);
      await preferences.setConsent(ConsentType.sensor, true);
      await preferences.setConsent(ConsentType.location, true);
      if (!mounted) return;
    }
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

  Future<void> _choose(String location) async {
    await ref.read(welcomeControllerProvider.notifier).complete();
    if (!mounted) return;
    context.go('$location?then=collect');
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
                    onCreateWallet: () => _choose('/wallet/create'),
                    onUsePasskey: () => _choose('/wallet/passkey'),
                    onImportWallet: () => _choose('/wallet/import'),
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
      title: 'Earn test WRF for your local weather data',
      body:
          'Your phone already has the sensors forecasters need. Every reading '
          'you contribute can earn WRF: no mining rig, no data centre, just your '
          'phone. This is a test network, so the coins have no money value.',
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
            'WRFCoin reads barometric pressure from the chip in your phone, and '
            'your location to place each reading on the map. You can turn '
            'either off in Privacy Center.',
            style: TextStyle(fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (!locationRequested)
            FilledButton.icon(
              onPressed: onRequestLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Allow sensors and location'),
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
  final VoidCallback onCreateWallet;
  final VoidCallback onUsePasskey;
  final VoidCallback onImportWallet;

  const _WalletSlide({
    required this.onCreateWallet,
    required this.onUsePasskey,
    required this.onImportWallet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so the slide works on small-height viewports and landscape.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your wallet is your account',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'No sign-up, email or phone number. Choose how to hold it.',
            style: TextStyle(fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('welcome-create-wallet'),
              onPressed: onCreateWallet,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create a 12-word wallet'),
            ),
          ),
          const SizedBox(height: 6),
          const _ChoiceNote(
            'Lives on this phone, and collects and earns here. You write 12 '
            'words on paper as your backup.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('welcome-use-passkey'),
              onPressed: onUsePasskey,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Use a passkey'),
            ),
          ),
          const SizedBox(height: 6),
          const _ChoiceNote(
            'Unlocks with your fingerprint or face in a browser tab, with no '
            'words to write down. Collecting on this phone still needs a '
            '12-word wallet.',
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('welcome-import-wallet'),
            onPressed: onImportWallet,
            child: const Text('I already have a 12-word wallet'),
          ),
        ],
      ),
    );
  }
}

class _ChoiceNote extends StatelessWidget {
  const _ChoiceNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
