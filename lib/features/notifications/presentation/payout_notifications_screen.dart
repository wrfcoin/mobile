import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_error_widget.dart';
import '../../../services/crypto/key_manager.dart';
import '../data/ntfy_poller.dart';
import '../data/payout_device.dart';
import '../data/payout_notifications.dart';

/// This device's wallet, lowercase, or null without one.
final payoutWalletProvider = FutureProvider.autoDispose<String?>((ref) async {
  final address = await ref.watch(keyManagerProvider).getAddress();
  final clean = address?.trim().toLowerCase();
  return clean == null || clean.isEmpty ? null : clean;
});

class PayoutNotificationsView {
  const PayoutNotificationsView({
    required this.config,
    this.address,
    this.signedIn = false,
    this.subscriptions = const [],
    this.deviceTopic,
  });

  final NotificationConfig config;
  final String? address;
  final bool signedIn;
  final List<NotificationSubscription> subscriptions;
  final String? deviceTopic;
}

final payoutNotificationsProvider =
    FutureProvider.autoDispose<Either<Failure, PayoutNotificationsView>>((
      ref,
    ) async {
      final repository = ref.watch(payoutNotificationRepositoryProvider);
      final address = await ref.watch(payoutWalletProvider.future);
      final deviceTopic = await ref.watch(payoutDeviceProvider).topic();
      final config = await repository.config();
      return config.fold<Future<Either<Failure, PayoutNotificationsView>>>(
        (failure) async => Left(failure),
        (config) async {
          PayoutNotificationsView view({
            bool signedIn = false,
            List<NotificationSubscription> subscriptions = const [],
          }) => PayoutNotificationsView(
            config: config,
            address: address,
            signedIn: signedIn,
            subscriptions: subscriptions,
            deviceTopic: deviceTopic,
          );
          if (!config.enabled || address == null) return Right(view());
          if (!await repository.hasSession()) return Right(view());
          final list = await repository.list(address);
          return list.fold(
            (failure) => failure is AuthFailure ? Right(view()) : Left(failure),
            (items) => Right(view(signedIn: true, subscriptions: items)),
          );
        },
      );
    });

/// "Tell me when this wallet is paid". The phone reads its own random ntfy
/// topic in the background and shows what arrives as a notification.
class PayoutNotificationsScreen extends ConsumerWidget {
  const PayoutNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(payoutNotificationsProvider);
    void retry() => ref.invalidate(payoutNotificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Payout notifications')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => AppErrorWidget(
              title: 'Notifications are unavailable right now',
              message: 'Nothing was changed; try again.',
              onRetry: retry,
            ),
            data: (result) => result.fold(
              (failure) => failure is NotAvailableFailure
                  ? _Plain(failure.message)
                  : AppErrorWidget.fromFailure(failure, onRetry: retry),
              (view) => view.config.enabled
                  ? _Body(view: view)
                  : const _Plain(
                      'Payout notifications are not switched on for this '
                      'network.',
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Plain extends StatelessWidget {
  const _Plain(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.view});

  final PayoutNotificationsView view;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _topic = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageOk = false;

  PayoutNotificationsView get view => widget.view;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  PayoutNotificationRepository get _repository =>
      ref.read(payoutNotificationRepositoryProvider);
  PayoutDevice get _device => ref.read(payoutDeviceProvider);

  void _say(String message, {bool ok = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageOk = ok;
    });
  }

  /// Runs [action], which returns the message to show on success.
  Future<void> _run(Future<Either<Failure, String>> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (failure) => _say(failure.message),
      (message) => _say(message, ok: true),
    );
    ref.invalidate(payoutNotificationsProvider);
  }

  Future<void> _turnOn() => _run(() async {
    final server = view.config.ntfyServer;
    if (server == null) {
      return const Left(
        ValidationFailure('ntfy is not set up on this server.'),
      );
    }
    if (!await _device.requestPermission()) {
      return const Left(
        ValidationFailure(
          'Notifications are blocked for this app. Allow them in your phone '
          'settings, then try again. Nothing was changed.',
        ),
      );
    }
    final topic = view.deviceTopic ?? _device.newTopic();
    final result = await _repository.subscribeTopic(view.address!, topic);
    return result.fold(Left.new, (_) async {
      await _device.enable(topic: topic, server: server);
      return const Right(
        'On. This phone will tell you when this wallet is paid.',
      );
    });
  });

  Future<void> _turnOff(String topic) => _run(() async {
    final result = await _repository.stopTopic(topic);
    return result.fold(Left.new, (_) async {
      await _device.disable();
      return const Right('Turned off for this phone.');
    });
  });

  Future<void> _test(NotificationSubscription subscription) => _run(() async {
    final result = await _repository.sendTest(subscription.id);
    return result.fold(Left.new, (delivered) async {
      if (!delivered) {
        return const Left(
          ValidationFailure('The test could not be delivered. Try again.'),
        );
      }
      if (subscription.label != view.deviceTopic) {
        return const Right('Test sent to the topic.');
      }
      // The server has handed it to ntfy; give ntfy a moment, then read.
      await Future<void>.delayed(ref.read(payoutTestSettleProvider));
      await _device.checkNow();
      return const Right('Test sent. It should appear in a few seconds.');
    });
  });

  Future<void> _addTopic() => _run(() async {
    final topic = _topic.text.trim();
    final result = await _repository.subscribeTopic(view.address!, topic);
    return result.map((_) {
      _topic.clear();
      return 'Added. Subscribe to "$topic" in the ntfy app.';
    });
  });

  Future<void> _remove(NotificationSubscription subscription) => _run(() async {
    final result = await _repository.remove(subscription.id);
    return result.map((_) => 'Removed.');
  });

  Future<void> _signIn() async {
    setState(() => _busy = true);
    final ok = await _repository.signIn();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(payoutNotificationsProvider);
    } else {
      _say('Sign-in did not finish. Nothing was changed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = view.config.checkEveryMinutes;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Node, station, forecast and producer pay all count.'
          '${minutes == null ? '' : ' The server checks about every $minutes minutes.'}'
          ' No email or name: only an address and a random topic are kept.',
        ),
        const SizedBox(height: 16),
        if (view.address == null)
          _Card(
            title: 'You need a wallet first',
            children: [
              const Text('Notifications are about a wallet being paid.'),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => context.go('/wallet'),
                child: const Text('Open your wallet'),
              ),
            ],
          )
        else if (!view.signedIn)
          _Card(
            title: 'Sign in with your wallet',
            children: [
              const Text(
                'Only the wallet that holds this address can change where its '
                'notifications go.',
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: const Text('Sign in'),
              ),
            ],
          )
        else ...[
          _phoneCard(),
          const SizedBox(height: 12),
          _topicsCard(),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _message!,
              style: TextStyle(
                color: _messageOk ? AppColors.success : AppColors.wcagWarning,
              ),
            ),
          ),
      ],
    );
  }

  NotificationSubscription? get _phoneSubscription {
    for (final subscription in view.subscriptions) {
      if (subscription.channel == 'ntfy' &&
          subscription.label == view.deviceTopic) {
        return subscription;
      }
    }
    return null;
  }

  Widget _phoneCard() {
    final subscription = _phoneSubscription;
    if (view.config.ntfyServer == null) {
      return const _Card(
        title: 'This phone',
        children: [
          Text('No notification channel is set up on this server yet.'),
        ],
      );
    }
    final host = Uri.parse(view.config.ntfyServer!).host;
    return _Card(
      title: 'This phone: ${subscription == null ? 'off' : 'on'}',
      children: [
        Text(
          'Your phone checks for news about every 15 minutes, when Android '
          "allows it. The check goes to $host, the free service that carries "
          "the message. It can see your phone's internet address, like any "
          'website.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (subscription == null)
          FilledButton(
            onPressed: _busy ? null : _turnOn,
            child: const Text('Turn on for this phone'),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : () => _test(subscription),
                child: const Text('Send a test'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _turnOff(subscription.label),
                child: const Text('Turn off'),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: subscription.label),
                  );
                  _say('Topic copied.', ok: true);
                },
                child: const Text('Copy topic for the ntfy app'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _topicsCard() {
    final others = view.subscriptions
        .where((s) => s.label != view.deviceTopic)
        .toList(growable: false);
    final topic = _topic.text.trim();
    return _Card(
      title: 'Other places',
      children: [
        const Text(
          'Prefer instant alerts, or another device? Subscribe to a topic in '
          'the free ntfy app, then add it here. Anyone who knows the topic '
          'can read it, so keep the random one.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _topic,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'ntfy topic',
            hintText: 'wrfcoin-pay-…',
            errorText: topic.isNotEmpty && !ntfyTopicPattern.hasMatch(topic)
                ? '12 to 64 letters, digits, - or _.'
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _topic.text = suggestNtfyTopic()),
              child: const Text('Random topic'),
            ),
            FilledButton(
              onPressed: _busy || !ntfyTopicPattern.hasMatch(topic)
                  ? null
                  : _addTopic,
              child: const Text('Add topic'),
            ),
          ],
        ),
        for (final subscription in others)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  subscription.channel == 'webpush'
                      ? 'Browser (${subscription.label})'
                      : subscription.label,
                ),
                if (subscription.channel == 'ntfy')
                  TextButton(
                    onPressed: _busy ? null : () => _test(subscription),
                    child: const Text('Send a test'),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => _remove(subscription),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// How long to wait after a test before reading the topic.
final payoutTestSettleProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}
