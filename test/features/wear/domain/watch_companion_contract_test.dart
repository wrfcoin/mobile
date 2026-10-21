import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wear/domain/watch_companion_contract.dart';

void main() {
  test('serializes and validates companion payload shape', () {
    final payload = WatchCompanionContract(
      pressureHpa: 1013.7,
      capturedAt: DateTime.utc(2026, 7, 30, 10, 15),
      platform: 'wearos',
      passiveCollectionEnabled: true,
      note: 'glance-ready',
    );

    final map = payload.toMap();
    expect(map['pressureHpa'], equals(1013.7));
    expect(map['platform'], equals('wearos'));
    expect(map['passiveCollectionEnabled'], isTrue);

    final parsed = WatchCompanionContract.fromMap(map);
    expect(parsed.pressureHpa, equals(1013.7));
    expect(parsed.platform, equals('wearos'));
    expect(parsed.passiveCollectionEnabled, isTrue);
    expect(parsed.capturedAt, equals(DateTime.utc(2026, 7, 30, 10, 15)));
    expect(parsed.note, equals('glance-ready'));
  });

  test('rejects invalid platform and missing timestamp', () {
    expect(
      () => WatchCompanionContract.fromMap({
        'pressureHpa': 1000,
        'platform': 'invalid',
        'capturedAt': '2026-07-30T10:00:00Z',
      }),
      throwsA(isA<WatchCompanionPayloadFormatException>()),
    );

    expect(
      () => WatchCompanionContract.fromMap({
        'pressureHpa': 1000,
        'platform': 'wearos',
      }),
      throwsA(isA<WatchCompanionPayloadFormatException>()),
    );
  });


  test('rejects a non-string note with the typed format exception', () {
    // Without the runtime guard the `as String?` cast would still reject this,
    // but as a raw TypeError rather than the contract's typed exception --
    // so this pins the guard, not merely that something throws.
    expect(
      () => WatchCompanionContract.fromMap({
        'pressureHpa': 1000,
        'platform': 'wearos',
        'capturedAt': '2026-07-30T10:00:00Z',
        'note': 42,
      }),
      throwsA(isA<WatchCompanionPayloadFormatException>()),
    );
  });
}
