sealed class Failure {
  final String message;
  final int? statusCode;

  const Failure(this.message, {this.statusCode});
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.statusCode});
}

class NotAvailableFailure extends Failure {
  final String? detail;

  const NotAvailableFailure(super.message, {this.detail, int statusCode = 501})
    : super(statusCode: statusCode);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class SecurityFailure extends Failure {
  const SecurityFailure([super.message = 'Secure connection failed']);
}
