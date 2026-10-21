import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/onboarding_controller.dart';

class OnboardingTourScreen extends ConsumerStatefulWidget {
  const OnboardingTourScreen({super.key});

  @override
  ConsumerState<OnboardingTourScreen> createState() =>
      _OnboardingTourScreenState();
}

class _OnboardingTourScreenState extends ConsumerState<OnboardingTourScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  bool _dontShowAgain = true;

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      title: 'Welcome',
      subtitle: 'Turn your phone into a weather station',
      description: 'WRFCoin collects local readings, improves forecasts, and rewards contributors with WRF. Start by connecting your first sensor.',
      icon: Icons.wb_sunny_outlined,
    ),
    _OnboardingPage(
      title: 'Setup',
      subtitle: 'Set up your first station',
      description: 'Connect a weather sensor or enable device readings. Sensors let you collect pressure, temperature, and humidity data continuously.',
      icon: Icons.sensors_outlined,
    ),
    _OnboardingPage(
      title: 'Earn',
      subtitle: 'Make your first submission',
      description: 'Each verified weather reading helps improve forecasts and earns you WRF tokens. Submissions sync automatically.',
      icon: Icons.toll_outlined,
    ),
  ];

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

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _skipToEnd() {
    _pageController.jumpToPage(_pages.length - 1);
  }

  void _finish() {
    ref
        .read(onboardingControllerProvider.notifier)
        .finish(dontShowAgain: _dontShowAgain);
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'WRFCoin Tour',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (!isLastPage)
                    TextButton(onPressed: _skipToEnd, child: const Text('Skip'))
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),
            // Progress indicators
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(right: 8),
                    height: 8,
                    width: index == _currentPage ? 24 : 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: index == _currentPage
                          ? Colors.blue
                          : Colors.grey.shade300,
                    ),
                  ),
                ),
              ),
            ),
            // Bottom buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: isLastPage
                  ? Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _finish,
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
                            label: const Text('Create Wallet'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _finish,
                            icon: const Icon(Icons.explore_outlined),
                            label: const Text('Explore First'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          value: _dontShowAgain,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Don't show again"),
                          onChanged: (value) {
                            setState(() {
                              _dontShowAgain = value ?? true;
                            });
                          },
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _currentPage == 0 ? null : _previousPage,
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _nextPage,
                            child: const Text('Next'),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(page.icon, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              page.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              page.subtitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              page.description,
              style: const TextStyle(fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;

  const _OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
  });
}
