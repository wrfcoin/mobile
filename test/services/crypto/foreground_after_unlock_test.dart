import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/crypto/foreground_after_unlock.dart';

void main() {
  const step = Duration(milliseconds: 10);

  test('already in the foreground: true at once, one check', () async {
    var checks = 0;
    expect(await waitForForeground(() => ++checks > 0, step: step), isTrue);
    expect(checks, 1);
  });

  test('resumed a moment later: true', () async {
    var checks = 0;
    expect(
      await waitForForeground(
        () => ++checks > 4,
        timeout: const Duration(seconds: 3),
        step: step,
      ),
      isTrue,
    );
    expect(checks, 5);
  });

  test('never resumed: false after the timeout', () async {
    final watch = Stopwatch()..start();
    expect(
      await waitForForeground(
        () => false,
        timeout: const Duration(milliseconds: 100),
        step: step,
      ),
      isFalse,
    );
    expect(
      watch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 100)),
    );
  });
}
