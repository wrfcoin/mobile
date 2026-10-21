import 'failures.dart';

class ErrorMessages {
  static String fromFailure(Failure failure) {
    return switch (failure) {
      NetworkFailure(:final message) =>
        message == 'No internet connection'
            ? 'No internet connection. Please check your network and try again.'
            : message,
      AuthFailure(:final message) =>
        message == 'Authentication failed'
            ? 'Session expired. Please sign in again.'
            : message,
      ServerFailure(:final statusCode, :final message) => switch (statusCode) {
        400 => 'Invalid request',
        401 => 'Session expired. Please sign in again.',
        403 => 'Access denied',
        404 => 'Not found',
        429 => 'Too many requests. Please wait a moment.',
        final code when code != null && code >= 500 && code < 600 =>
          'Server error. Please try again later.',
        _ => message,
      },
      NotAvailableFailure(:final message) => message,
      ValidationFailure(:final message) => message,
      CacheFailure(:final message) =>
        message == 'Cache error'
            ? 'Local storage error. Please restart the app.'
            : message,
      SecurityFailure(:final message) => message,
    };
  }
}
