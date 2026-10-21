import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

enum AuthHandoffReason {
  sessionExpired,
  unsupportedWallet,

  /// No session and no automatic way to get one (mobile#320): only the
  /// user's Sign in can start a login. The wallet screen offers it; the
  /// rest of the app stays usable, so this never gates navigation.
  notSignedIn,
}

class AuthHandoffController extends ChangeNotifier {
  AuthHandoffReason? _reason;
  String? _message;

  AuthHandoffReason? get reason => _reason;
  String? get message => _message;
  bool get requiresWalletConnect => _reason != null;

  /// Whether the app should send the user to the wallet screen: a session
  /// problem that needs their attention, not merely being signed out.
  bool get gatesNavigation =>
      _reason != null && _reason != AuthHandoffReason.notSignedIn;

  /// Whether the wallet UI should offer Sign in for this handoff.
  bool get offersSignIn =>
      _reason == AuthHandoffReason.sessionExpired ||
      _reason == AuthHandoffReason.notSignedIn;

  void requireWalletConnect({
    required AuthHandoffReason reason,
    required String message,
  }) {
    _reason = reason;
    _message = message;
    notifyListeners();
  }

  void clear() {
    if (_reason == null && _message == null) return;
    _reason = null;
    _message = null;
    notifyListeners();
  }
}

final authHandoffControllerProvider =
    ChangeNotifierProvider<AuthHandoffController>((ref) {
      return AuthHandoffController();
    });
