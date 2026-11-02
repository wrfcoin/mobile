import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/notifications/data/payout_device.dart';
import 'package:wrfcoin_mobile/features/notifications/data/payout_notifications.dart';
import 'package:wrfcoin_mobile/features/notifications/presentation/payout_notifications_screen.dart';
import 'package:wrfcoin_mobile/services/notifications/push_service.dart';

const _address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _topic = 'wrfcoin-pay-0011223344556677';
const _config = NotificationConfig(
  enabled: true,
  checkEveryMinutes: 5,
  ntfyServer: 'https://ntfy.sh',
);

class _Repository implements PayoutNotificationRepository {
  Either<Failure, NotificationConfig> configAnswer = const Right(_config);
  bool session = true;
  List<NotificationSubscription> subscriptions = [];
  Failure? refusal;
  bool delivered = true;
  bool signInWorks = true;
  final List<String> calls = [];

  Either<Failure, T> _answer<T>(String call, T value) {
    calls.add(call);
    return refusal != null ? Left(refusal!) : Right(value);
  }

  @override
  Future<Either<Failure, NotificationConfig>> config() async => configAnswer;

  @override
  Future<bool> hasSession() async => session;

  @override
  Future<bool> signIn() async {
    calls.add('signIn');
    session = signInWorks;
    return signInWorks;
  }

  @override
  Future<Either<Failure, List<NotificationSubscription>>> list(
    String address,
  ) async => Right(subscriptions);

  @override
  Future<Either<Failure, NotificationSubscription>> subscribeTopic(
    String address,
    String topic,
  ) async {
    final item = NotificationSubscription(
      id: 'id-$topic',
      channel: 'ntfy',
      label: topic,
    );
    final answer = _answer('subscribe:$topic', item);
    if (answer.isRight()) subscriptions = [...subscriptions, item];
    return answer;
  }

  @override
  Future<Either<Failure, Unit>> remove(String id) async {
    final answer = _answer('remove:$id', unit);
    if (answer.isRight()) {
      subscriptions = subscriptions.where((s) => s.id != id).toList();
    }
    return answer;
  }

  @override
  Future<Either<Failure, bool>> sendTest(String id) async =>
      _answer('test:$id', delivered);

  @override
  Future<Either<Failure, Unit>> stopTopic(String topic) async {
    final answer = _answer('stop:$topic', unit);
    if (answer.isRight()) {
      subscriptions = subscriptions.where((s) => s.label != topic).toList();
    }
    return answer;
  }
}

class _Device extends PayoutDevice {
  _Device({this.stored}) : super(PushService());

  String? stored;
  bool permission = true;
  int checks = 0;
  final List<String> calls = [];

  @override
  Future<bool> requestPermission() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<String?> topic() async => stored;

  @override
  String newTopic() => _topic;

  @override
  Future<void> enable({required String topic, required String server}) async {
    calls.add('enable:$topic@$server');
    stored = topic;
  }

  @override
  Future<void> disable() async {
    calls.add('disable');
    stored = null;
  }

  @override
  Future<int> checkNow() async {
    checks++;
    return 1;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Repository repository,
  _Device device, {
  String? wallet = _address,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        payoutNotificationRepositoryProvider.overrideWithValue(repository),
        payoutDeviceProvider.overrideWithValue(device),
        payoutWalletProvider.overrideWith((ref) async => wallet),
        payoutTestSettleProvider.overrideWithValue(Duration.zero),
      ],
      child: const MaterialApp(home: PayoutNotificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loading: a spinner, no claim either way', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          payoutNotificationsProvider.overrideWith(
            (ref) => Future.delayed(
              const Duration(days: 1),
              () => const Left(NetworkFailure()),
            ),
          ),
        ],
        child: const MaterialApp(home: PayoutNotificationsScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('This phone'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(days: 2));
  });

  testWidgets('empty: off, and offers to turn on', (tester) async {
    await _pump(tester, _Repository(), _Device());
    expect(find.text('This phone: off'), findsOneWidget);
    expect(find.text('Turn on for this phone'), findsOneWidget);
    expect(find.textContaining('ntfy.sh'), findsOneWidget);
    expect(find.textContaining('No email or name'), findsOneWidget);
  });

  testWidgets('loaded: on, with test and turn off', (tester) async {
    final repository = _Repository()
      ..subscriptions = const [
        NotificationSubscription(id: 'p', channel: 'ntfy', label: _topic),
        NotificationSubscription(
          id: 'o',
          channel: 'ntfy',
          label: 'my-other-topic-1',
        ),
        NotificationSubscription(
          id: 'b',
          channel: 'webpush',
          label: 'fcm.example',
        ),
      ];
    await _pump(tester, repository, _Device(stored: _topic));
    expect(find.text('This phone: on'), findsOneWidget);
    expect(find.text('Turn off'), findsOneWidget);
    expect(find.text('my-other-topic-1'), findsOneWidget);
    expect(find.text('Browser (fcm.example)'), findsOneWidget);
    expect(find.text('Remove'), findsNWidgets(2));
  });

  testWidgets('error: not "off", with a retry that works', (tester) async {
    final repository = _Repository()
      ..configAnswer = const Left(ServerFailure('down', statusCode: 503));
    await _pump(tester, repository, _Device());
    expect(find.textContaining('This phone'), findsNothing);
    repository.configAnswer = const Right(_config);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('This phone: off'), findsOneWidget);
  });

  testWidgets('server has it off: says so', (tester) async {
    final repository = _Repository()
      ..configAnswer = const Right(
        NotificationConfig(
          enabled: false,
          checkEveryMinutes: null,
          ntfyServer: null,
        ),
      );
    await _pump(tester, repository, _Device());
    expect(find.textContaining('not switched on'), findsOneWidget);
  });

  testWidgets('no wallet: points at the wallet', (tester) async {
    await _pump(tester, _Repository(), _Device(), wallet: null);
    expect(find.text('Open your wallet'), findsOneWidget);
    expect(find.text('Turn on for this phone'), findsNothing);
  });

  testWidgets('signed out: sign in, then the controls appear', (tester) async {
    final repository = _Repository()..session = false;
    await _pump(tester, repository, _Device());
    expect(find.text('Turn on for this phone'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['signIn']);
    expect(find.text('Turn on for this phone'), findsOneWidget);
  });

  testWidgets('a failed sign-in says so', (tester) async {
    final repository = _Repository()
      ..session = false
      ..signInWorks = false;
    await _pump(tester, repository, _Device());
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('did not finish'), findsOneWidget);
  });

  testWidgets('turn on: asks the OS, subscribes, then starts checking', (
    tester,
  ) async {
    final repository = _Repository();
    final device = _Device();
    await _pump(tester, repository, device);
    await tester.tap(find.text('Turn on for this phone'));
    await tester.pumpAndSettle();
    expect(device.calls, ['permission', 'enable:$_topic@https://ntfy.sh']);
    expect(repository.calls, ['subscribe:$_topic']);
    expect(find.text('This phone: on'), findsOneWidget);
    expect(find.textContaining('On. This phone will tell you'), findsOneWidget);
  });

  testWidgets('a refused permission changes nothing', (tester) async {
    final repository = _Repository();
    final device = _Device()..permission = false;
    await _pump(tester, repository, device);
    await tester.tap(find.text('Turn on for this phone'));
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    expect(device.calls, ['permission']);
    expect(find.textContaining('blocked for this app'), findsOneWidget);
  });

  testWidgets('a refused subscribe does not start checking', (tester) async {
    final repository = _Repository();
    final device = _Device();
    await _pump(tester, repository, device);
    repository.refusal = const ValidationFailure('This address is full.');
    await tester.tap(find.text('Turn on for this phone'));
    await tester.pump();
    await tester.pump();
    expect(device.calls, ['permission']);
    expect(find.text('This address is full.'), findsOneWidget);
    repository.refusal = null;
    await tester.pumpAndSettle();
    expect(find.text('This phone: off'), findsOneWidget);
  });

  testWidgets('send a test: the phone reads its topic right away', (
    tester,
  ) async {
    final repository = _Repository()
      ..subscriptions = const [
        NotificationSubscription(id: 'p', channel: 'ntfy', label: _topic),
      ];
    final device = _Device(stored: _topic);
    await _pump(tester, repository, device);
    await tester.tap(find.text('Send a test'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['test:p']);
    expect(device.checks, 1);
    expect(find.textContaining('Test sent.'), findsOneWidget);
  });

  testWidgets('an undelivered test is not called sent', (tester) async {
    final repository = _Repository()
      ..delivered = false
      ..subscriptions = const [
        NotificationSubscription(id: 'p', channel: 'ntfy', label: _topic),
      ];
    final device = _Device(stored: _topic);
    await _pump(tester, repository, device);
    await tester.tap(find.text('Send a test'));
    await tester.pumpAndSettle();
    expect(device.checks, 0);
    expect(find.textContaining('could not be delivered'), findsOneWidget);
  });

  testWidgets('turn off: stops the topic, then the checking', (tester) async {
    final repository = _Repository()
      ..subscriptions = const [
        NotificationSubscription(id: 'p', channel: 'ntfy', label: _topic),
      ];
    final device = _Device(stored: _topic);
    await _pump(tester, repository, device);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['stop:$_topic']);
    expect(device.calls, ['disable']);
    expect(find.text('This phone: off'), findsOneWidget);
  });

  testWidgets('a failed turn off keeps checking, so it stays true', (
    tester,
  ) async {
    final repository = _Repository()
      ..subscriptions = const [
        NotificationSubscription(id: 'p', channel: 'ntfy', label: _topic),
      ];
    final device = _Device(stored: _topic);
    await _pump(tester, repository, device);
    repository.refusal = const ValidationFailure('Nothing was changed.');
    await tester.tap(find.text('Turn off'));
    await tester.pump();
    await tester.pump();
    expect(device.calls, isEmpty);
    repository.refusal = null;
    await tester.pumpAndSettle();
  });

  testWidgets('add topic: refuses a short one, adds a good one', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository, _Device());
    final add = find.widgetWithText(FilledButton, 'Add topic');
    await tester.enterText(find.byType(TextField), 'short');
    await tester.pump();
    expect(find.text('12 to 64 letters, digits, - or _.'), findsOneWidget);
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'my-own-topic-123');
    await tester.pump();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(repository.calls, ['subscribe:my-own-topic-123']);
    expect(find.text('my-own-topic-123'), findsOneWidget);
  });

  testWidgets('random topic fills a valid one', (tester) async {
    await _pump(tester, _Repository(), _Device());
    await tester.tap(find.text('Random topic'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(ntfyTopicPattern.hasMatch(field.controller!.text), isTrue);
  });

  final fonts = Platform.environment['SCREENSHOT_FONTS'];
  Future<void> load(String family, String file) async {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(
          ByteData.sublistView(File('$fonts/$file').readAsBytesSync()),
        ),
      );
    await loader.load();
  }

  // Renders with SCREENSHOT_FONTS set to Flutter's bin/cache/artifacts/material_fonts
  // and --update-goldens. The data is a synthetic fixture.
  const widths = {'phone': Size(390, 900), 'desktop': Size(1280, 800)};
  for (final MapEntry(key: name, value: size) in widths.entries) {
    testWidgets('$name screenshot', (tester) async {
      await load('Roboto', 'Roboto-Regular.ttf');
      await load('MaterialIcons', 'MaterialIcons-Regular.otf');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository()
        ..subscriptions = const [
          NotificationSubscription(id: 'p', channel: 'ntfy', label: _topic),
          NotificationSubscription(
            id: 'o',
            channel: 'ntfy',
            label: 'wrfcoin-pay-a1b2c3d4e5f60718',
          ),
        ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            payoutNotificationRepositoryProvider.overrideWithValue(repository),
            payoutDeviceProvider.overrideWithValue(_Device(stored: _topic)),
            payoutWalletProvider.overrideWith((ref) async => _address),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme.copyWith(
              textTheme: AppTheme.darkTheme.textTheme.apply(
                fontFamily: 'Roboto',
              ),
            ),
            home: const PayoutNotificationsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../../docs/screenshots/payout-notifications/screen-$name.png',
        ),
      );
    }, skip: fonts == null);
  }
}
