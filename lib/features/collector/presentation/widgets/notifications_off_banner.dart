import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/background/collection_service.dart';
import '../../../../services/location/location_service.dart';
import '../providers/collector_provider.dart';

const notificationsOffBannerText =
    "Notifications are off, so we can't tell you when collection stops.";

/// Whether the app may post notifications (null: unknown or no service).
final collectionNotificationsAllowedProvider =
    FutureProvider.autoDispose<bool?>(
      (ref) => ref.watch(collectionServiceProvider).notificationsAllowed,
    );

/// Shown on Collect while Collect is on and notifications are off. When the
/// phone stops the collection service in the background, a notification is
/// the only way the app can say so; with notifications off the user would
/// never hear of it. Checked again whenever the app comes back to the
/// screen, so the banner goes away once notifications are allowed.
class NotificationsOffBanner extends ConsumerStatefulWidget {
  const NotificationsOffBanner({super.key});

  @override
  ConsumerState<NotificationsOffBanner> createState() =>
      _NotificationsOffBannerState();
}

class _NotificationsOffBannerState extends ConsumerState<NotificationsOffBanner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(collectionNotificationsAllowedProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collecting = ref.watch(
      collectorProvider.select((state) => state.isCollecting),
    );
    final allowed = ref.watch(collectionNotificationsAllowedProvider).value;
    if (!collecting || allowed != false) return const SizedBox.shrink();
    return Padding(
      key: const Key('notifications-off-banner'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: AppColors.warning.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_off_outlined,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text(notificationsOffBannerText)),
              TextButton(
                onPressed: () =>
                    ref.read(locationServiceProvider).openAppSettings(),
                child: const Text('Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
