import 'package:dio/dio.dart';

import 'failures.dart';

/// Error code backend#1199 sends with a 503 when its core4 Reader credential
/// is not configured.
const String core4ReaderCredentialUnconfigured =
    'CORE4_READER_CREDENTIAL_UNCONFIGURED';

class DioErrorMapper {
  static Failure map(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return const NetworkFailure(
          'Connection timed out. Check your internet and try again.',
        );
      case DioExceptionType.receiveTimeout:
        return const ServerFailure('Server took too long to respond.');
      case DioExceptionType.connectionError:
        return const NetworkFailure('No internet connection.');
      case DioExceptionType.badResponse:
        return _mapBadResponse(error);
      case DioExceptionType.badCertificate:
        return const SecurityFailure(
          'Secure connection could not be verified. '
          'Please switch to a trusted network and try again.',
        );
      // `transformTimeout` was added in dio 5.10; it fires when decoding or
      // transforming an otherwise-successful response exceeds the budget.
      // Treated as a server-side slowness failure, matching `receiveTimeout`.
      case DioExceptionType.transformTimeout:
        return const ServerFailure('Server took too long to respond.');
      case DioExceptionType.cancel:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.unknown:
        return ServerFailure(
          _extractMessage(error) ?? 'Something went wrong. Please try again.',
          statusCode: error.response?.statusCode,
        );
    }
  }

  static Failure _mapBadResponse(DioException error) {
    final statusCode = error.response?.statusCode;
    final fallbackMessage =
        _extractMessage(error) ?? 'Server error. Please try again later.';

    if (statusCode == 401) {
      return const AuthFailure('Not signed in. Tap Sign in to continue.');
    }

    if (statusCode == 501) {
      return NotAvailableFailure(
        _extractMessage(error) ??
            'This feature is not available on the testnet yet.',
        detail: _extractDetail(error),
      );
    }

    // backend#1199: the backend has no core4 Reader credential configured.
    // That is a lasting deployment gap, not a transient fault, so a retry
    // never helps; surface it as "not available" rather than a server error.
    if (statusCode == 503 &&
        _extractCode(error) == core4ReaderCredentialUnconfigured) {
      return NotAvailableFailure(
        _extractMessage(error) ??
            'This feature is not available on this server yet.',
        detail: core4ReaderCredentialUnconfigured,
        statusCode: 503,
      );
    }

    if (statusCode != null && statusCode >= 500 && statusCode < 600) {
      return const ServerFailure('Server error. Please try again later.');
    }

    return ServerFailure(fallbackMessage, statusCode: statusCode);
  }

  static String? _extractCode(DioException error) {
    final data = error.response?.data;
    if (data is! Map<String, dynamic>) return null;
    final nested = data['error'];
    final value = (nested is Map ? nested['code'] : null) ?? data['code'];
    return value?.toString();
  }

  static String? _extractMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final nested = data['error'];
      final value =
          data['message'] ??
          (nested is Map ? nested['message'] : nested) ??
          data['reason'];
      if (value != null) {
        return value.toString();
      }
    }

    return error.message;
  }

  static String? _extractDetail(DioException error) {
    final data = error.response?.data;
    if (data is! Map<String, dynamic>) return null;
    final nested = data['error'];
    final value =
        data['reason'] ??
        data['detail'] ??
        data['details'] ??
        (nested is Map ? nested['details'] : null);
    return value?.toString();
  }
}
