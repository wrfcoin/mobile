import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The one way into Settings: the same gear at the top of every main tab.
///
/// It pushes, so Back returns to the tab it was opened from and that tab stays
/// selected in the navigation bar.
class SettingsGearButton extends StatelessWidget {
  const SettingsGearButton({super.key});

  static const String route = '/profile/settings';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open settings',
      child: IconButton(
        tooltip: 'Settings',
        icon: const Icon(Icons.settings),
        onPressed: () => context.push(route),
      ),
    );
  }
}
