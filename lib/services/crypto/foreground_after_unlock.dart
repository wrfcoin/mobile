import 'dart:async';

/// How long to wait, after a device unlock, for the app to be back in the
/// foreground before refusing to sign.
const Duration foregroundAfterUnlockTimeout = Duration(seconds: 3);

/// Waits until [isForeground] is true, checking every [step], for up to
/// [timeout]. True as soon as it is; false if it never is.
///
/// Why wait at all: on Android the unlock with the device PIN or pattern is a
/// separate system screen, so the app's activity is paused while it shows.
/// local_auth completes the unlock (BiometricPrompt `onAuthenticationSucceeded`)
/// before the activity's `onResume` reaches Flutter, so straight after a
/// successful unlock the lifecycle is often still `paused` or `inactive`,
/// and it turns `resumed` a moment later. Treating `inactive` as foreground
/// would not cover the `paused` case. Waiting briefly for a real `resumed`
/// keeps the rule "sign only while the app is on screen" without refusing
/// the person who just unlocked.
Future<bool> waitForForeground(
  bool Function() isForeground, {
  Duration timeout = foregroundAfterUnlockTimeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  if (isForeground()) return true;
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    await Future<void>.delayed(step);
    if (isForeground()) return true;
  }
  return false;
}
