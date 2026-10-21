import 'package:flutter/material.dart';

import '../../../sky_view/presentation/sky_view_screen.dart';

/// Retains the existing /weather/ar route while Sky View lives in its own feature.
class ArViewerScreen extends StatelessWidget {
  const ArViewerScreen({super.key});

  @override
  Widget build(BuildContext context) => const SkyViewScreen();
}
