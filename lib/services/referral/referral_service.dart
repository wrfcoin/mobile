import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/api_constants.dart';
import '../api/api_client.dart';

final referralServiceProvider = Provider<ReferralService>((ref) {
  return ReferralService(apiClient: ref.watch(apiClientProvider));
});

/// Manages referral invite codes and attribution.
///
/// The service asks the backend for idempotent referral-code generation,
/// creates shareable invite deep-links, and stores any captured invite code
/// until the user completes wallet signup/import.
class ReferralService {
  ReferralService({required ApiClient apiClient, this._prefs})
    : _dio = apiClient.dio;

  static const _pendingReferralCodeKey = 'referral.pending_code';
  static const _pendingReferralCapturedAtKey = 'referral.pending_captured_at';

  final Dio _dio;
  SharedPreferences? _prefs;

  /// Requests a unique referral code for [walletAddress] from the backend.
  ///
  /// The backend keeps the operation idempotent, so repeated calls for the
  /// same wallet will return the existing pending code.
  Future<String> generateReferralCode(String walletAddress) async {
    final normalizedAddress = walletAddress.trim();
    if (normalizedAddress.isEmpty) {
      throw ArgumentError.value(
        walletAddress,
        'walletAddress',
        'must not be empty',
      );
    }

    final response = await _dio.post(
      ApiConstants.referralGenerate,
      data: {'walletAddress': normalizedAddress},
    );
    final payload = _unwrapMap(response.data);
    final referralCode = payload['referralCode']?.toString().trim();
    if (referralCode == null || referralCode.isEmpty) {
      throw StateError('Referral API did not return a referralCode');
    }
    return referralCode;
  }

  /// Builds the app invite deep-link for a referral code.
  ///
  /// Example: `wrfcoin://invite?ref=ABC123`
  String createInviteDeepLink(String referralCode) {
    final normalized = referralCode.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        referralCode,
        'referralCode',
        'must not be empty',
      );
    }

    return Uri(
      scheme: 'wrfcoin',
      host: 'invite',
      queryParameters: {'ref': normalized},
    ).toString();
  }

  /// Extracts a referral code from an invite URI.
  String? extractReferralCode(Uri uri) {
    final isInviteHost = uri.host == 'invite';
    final isInvitePath =
        uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'invite';

    if (uri.scheme.isNotEmpty && uri.scheme != 'wrfcoin') return null;
    if (!isInviteHost && !isInvitePath) return null;

    final code = uri.queryParameters['ref']?.trim();
    if (code == null || code.isEmpty) return null;
    return code;
  }

  /// Stores a referral code until the wallet signup/import flow completes.
  Future<void> storePendingReferralCode(String referralCode) async {
    final normalized = referralCode.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        referralCode,
        'referralCode',
        'must not be empty',
      );
    }

    final prefs = await _getPrefs();
    await Future.wait([
      prefs.setString(_pendingReferralCodeKey, normalized),
      prefs.setString(
        _pendingReferralCapturedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      ),
    ]);
  }

  /// Captures a referral from a deep-link URI.
  Future<bool> captureInviteUri(Uri uri) async {
    final referralCode = extractReferralCode(uri);
    if (referralCode == null) return false;
    await storePendingReferralCode(referralCode);
    return true;
  }

  /// Captures a referral from the raw link text.
  Future<bool> captureInviteLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return false;
    return captureInviteUri(uri);
  }

  Future<String?> getPendingReferralCode() async {
    final prefs = await _getPrefs();
    final code = prefs.getString(_pendingReferralCodeKey)?.trim();
    return code?.isEmpty == true ? null : code;
  }

  Future<String?> getPendingReferralCapturedAt() async {
    final prefs = await _getPrefs();
    final capturedAt = prefs.getString(_pendingReferralCapturedAtKey)?.trim();
    return capturedAt?.isEmpty == true ? null : capturedAt;
  }

  Future<void> clearPendingReferralCode() async {
    final prefs = await _getPrefs();
    await Future.wait([
      prefs.remove(_pendingReferralCodeKey),
      prefs.remove(_pendingReferralCapturedAtKey),
    ]);
  }

  /// Activates any pending referral attribution for the newly created wallet.
  ///
  /// Returns `true` if the backend accepted the attribution and `false` when
  /// no code was present or activation failed. Network failures are treated as
  /// non-fatal so onboarding can continue.
  Future<bool> trackReferralAttributionOnSignup({
    required String refereeAddress,
  }) async {
    final code = await getPendingReferralCode();
    final normalizedReferee = refereeAddress.trim();
    if (code == null || normalizedReferee.isEmpty) {
      return false;
    }

    try {
      await _dio.post(
        ApiConstants.referralActivate,
        data: {'referralCode': code, 'refereeAddress': normalizedReferee},
      );
      await clearPendingReferralCode();
      return true;
    } on DioException catch (error) {
      if (error.response != null) {
        await clearPendingReferralCode();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Map<String, dynamic> _unwrapMap(dynamic payload) {
    dynamic current = payload;

    while (current is Map) {
      final map = Map<String, dynamic>.from(current);
      final nested = map['data'];
      if (nested is Map) {
        current = nested;
        continue;
      }
      return map;
    }

    throw StateError('Expected referral API response to be an object.');
  }
}
