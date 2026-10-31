import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/send_allowlist.dart';

const _mom = '0x1111111111111111111111111111111111111111';
const _stranger = '0x2222222222222222222222222222222222222222';

void main() {
  late DateTime now;
  late SendAllowlistPolicy policy;

  setUp(() {
    now = DateTime.utc(2026, 11, 1, 12);
    policy = SendAllowlistPolicy(clock: () => now);
  });

  const on = SendAllowlistSettings(enabled: true);
  const momEntry = AddressBookEntry(label: 'Mom', address: _mom);

  group('turning on and off', () {
    test('off by default; turning on is instant', () {
      expect(policy.isOn(SendAllowlistSettings.off), isFalse);
      final s = policy.turnOn(SendAllowlistSettings.off);
      expect(policy.isOn(s), isTrue);
      expect(s.turnsOffAt, isNull);
    });

    test('turning off waits 24 hours, then settles to off', () {
      final s = policy.requestTurnOff(on);
      expect(s.turnsOffAt, now.add(const Duration(hours: 24)));
      expect(policy.isOn(s), isTrue);

      now = now.add(const Duration(hours: 23, minutes: 59));
      expect(policy.isOn(s), isTrue);
      expect(policy.settle(s), s);

      now = now.add(const Duration(minutes: 1));
      expect(policy.isOn(s), isFalse);
      expect(policy.settle(s), SendAllowlistSettings.off);
    });

    test('a second turn-off request does not move the pending time', () {
      final first = policy.requestTurnOff(on);
      now = now.add(const Duration(hours: 5));
      expect(policy.requestTurnOff(first), first);
    });

    test('a pending turn-off can be cancelled', () {
      final pending = policy.requestTurnOff(on);
      now = now.add(const Duration(hours: 3));
      final s = policy.cancelTurnOff(pending);
      expect(s, on);
      now = now.add(const Duration(days: 2));
      expect(policy.isOn(s), isTrue);
    });

    test('turning on again during a pending turn-off cancels it', () {
      final pending = policy.requestTurnOff(on);
      expect(policy.turnOn(pending), on);
    });

    test('settings round-trip through JSON', () {
      final pending = policy.requestTurnOff(on);
      expect(SendAllowlistSettings.fromJson(pending.toJson()), pending);
      expect(
        SendAllowlistSettings.fromJson(const {}),
        SendAllowlistSettings.off,
      );
    });
  });

  group('allowing contacts', () {
    test('allowing while the allowlist is off is instant', () {
      final e = policy.allow(momEntry, SendAllowlistSettings.off);
      expect(e.allowedFrom, now);
      expect(policy.stateOf(e), ContactAllowState.allowed);
    });

    test('allowing while on waits 24 hours', () {
      final e = policy.allow(momEntry, on);
      expect(policy.stateOf(e), ContactAllowState.pending);
      expect(e.allowedFrom, now.add(sendAllowlistCooldown));
      now = now.add(sendAllowlistCooldown);
      expect(policy.stateOf(e), ContactAllowState.allowed);
    });

    test('allowing again never moves an existing allowance', () {
      final e = policy.allow(momEntry, on);
      now = now.add(const Duration(hours: 10));
      expect(policy.allow(e, on).allowedFrom, e.allowedFrom);
    });

    test('revoking is instant', () {
      final e = policy.revoke(
        policy.allow(momEntry, SendAllowlistSettings.off),
      );
      expect(policy.stateOf(e), ContactAllowState.notAllowed);
    });

    test('allowance survives the JSON round-trip', () {
      final e = policy.allow(momEntry, on);
      final back = AddressBookEntry.fromJson(e.toJson());
      expect(back.allowedFrom, e.allowedFrom);
      expect(back.label, 'Mom');
    });
  });

  group('checking a send', () {
    test('everything is allowed while the allowlist is off', () {
      final v = policy.check(
        to: _stranger,
        book: const [],
        settings: SendAllowlistSettings.off,
      );
      expect(v.blocksSend, isFalse);
    });

    test('an unsaved address is refused while on', () {
      final v = policy.check(
        to: _stranger,
        book: const [momEntry],
        settings: on,
      );
      expect(v.kind, AllowlistVerdictKind.notSaved);
      expect(v.blocksSend, isTrue);
    });

    test('a saved but not allowed contact is refused', () {
      final v = policy.check(to: _mom, book: const [momEntry], settings: on);
      expect(v.kind, AllowlistVerdictKind.notAllowed);
      expect(v.contact?.label, 'Mom');
    });

    test('a pending contact is refused until its time, matching any case', () {
      final pending = policy.allow(momEntry, on);
      final v = policy.check(
        to: _mom.toUpperCase().replaceFirst('0X', '0x'),
        book: [pending],
        settings: on,
      );
      expect(v.kind, AllowlistVerdictKind.pending);
      expect(v.allowedFrom, now.add(sendAllowlistCooldown));

      now = now.add(sendAllowlistCooldown);
      expect(
        policy.check(to: _mom, book: [pending], settings: on).blocksSend,
        isFalse,
      );
    });

    test('a pending turn-off still guards sends until it applies', () {
      final pending = policy.requestTurnOff(on);
      expect(
        policy
            .check(to: _stranger, book: const [], settings: pending)
            .blocksSend,
        isTrue,
      );
      now = now.add(sendAllowlistCooldown);
      expect(
        policy
            .check(to: _stranger, book: const [], settings: pending)
            .blocksSend,
        isFalse,
      );
    });
  });

  test('the help text is exactly what the owner asked for', () {
    expect(
      sendAllowlistScopeNote,
      'This protects you from mistakes in this app. For protection against a '
      'stolen phrase, see the on-chain allowlist (coming)',
    );
  });
}
