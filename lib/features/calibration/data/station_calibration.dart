import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../services/api/api_client.dart';
import '../../collector/data/services/station_owner_api.dart';

/// Station calibration certificates (backend calibration-certificate-routes.ts).
/// A trust root signs a certificate for a station's public alias, and the
/// backend re-verifies it on every read. Parsing is fail-closed: an answer this
/// app cannot read is an error, never shown as "calibrated".
enum CalibrationStatus {
  calibrated('calibrated', 'Calibrated'),
  expired('expired', 'Calibration expired'),
  revoked('revoked', 'Calibration revoked'),
  notTrusted('not_trusted', 'Calibration not trusted'),
  invalid('invalid', 'Calibration invalid'),
  none('none', 'Not calibrated');

  const CalibrationStatus(this.wire, this.label);

  final String wire;
  final String label;

  String get detail => switch (this) {
    calibrated =>
      "A trusted calibrator signed a certificate for this station's sensor, "
          'and it is valid now.',
    expired =>
      "This station's newest calibration certificate has passed its expiry "
          'date.',
    revoked =>
      "The calibrator withdrew this station's newest calibration certificate.",
    notTrusted =>
      "This station's certificate was signed by a key that is not a trusted "
          'calibrator on this network.',
    invalid => "This station's newest certificate did not pass verification.",
    none => 'No calibration certificate has been issued for this station yet.',
  };
}

const Map<String, String> calibrationRevocationReasons = {
  'superseded': 'replaced by a newer certificate',
  'sensor_replaced': 'the sensor was replaced',
  'sensor_moved': 'the sensor was moved',
  'calibration_error': 'the calibration was found to be wrong',
  'key_compromise': 'the signing key was compromised',
  'other': 'other reason',
};

class CalibrationRevocation {
  const CalibrationRevocation({required this.reason, required this.revokedAt});

  final String reason;
  final DateTime revokedAt;
}

class CalibrationCertificate {
  const CalibrationCertificate({
    required this.cid,
    required this.artifactId,
    required this.issuerId,
    required this.issuedAt,
    required this.expiresAt,
    this.ownerAddress,
    this.sensor,
    this.method,
    this.reference,
    this.notes,
    this.revocation,
  });

  final String cid;
  final String artifactId;
  final String issuerId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String? ownerAddress;
  final String? sensor;
  final String? method;
  final String? reference;
  final String? notes;
  final CalibrationRevocation? revocation;
}

class StationCalibration {
  const StationCalibration({
    required this.stationAlias,
    required this.status,
    this.certificate,
    this.signedCertificate,
  });

  final String stationAlias;
  final CalibrationStatus status;
  final CalibrationCertificate? certificate;

  /// The full signed certificate, so anyone can check it against the
  /// calibrator's public key.
  final Object? signedCertificate;

  /// Throws [FormatException] for any answer that does not match the contract.
  factory StationCalibration.fromJson(Object? body) {
    Never bad() => throw const FormatException(
      'Station calibration status has an unexpected shape.',
    );
    DateTime date(Object? value) {
      final parsed = value is String ? DateTime.tryParse(value) : null;
      return parsed ?? bad();
    }

    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;

    if (body is! Map) bad();
    final alias = body['stationAlias'];
    if (alias is! String) bad();
    date(body['checkedAt']);
    if (body['trustRoots'] is! List) bad();
    final status = CalibrationStatus.values.firstWhere(
      (value) => value.wire == body['status'],
      orElse: () => bad(),
    );
    final raw = body['certificate'];
    if (status == CalibrationStatus.none) {
      if (raw != null) bad();
      return StationCalibration(stationAlias: alias, status: status);
    }
    if (raw is! Map || raw['status'] != status.wire) bad();
    final cid = raw['cid'];
    final artifactId = raw['artifactId'];
    final issuer = raw['issuer'];
    if (cid is! String || artifactId is! String || issuer is! Map) bad();
    final issuerId = issuer['issuerId'];
    if (issuerId is! String) bad();
    final details = raw['calibration'] is Map
        ? raw['calibration'] as Map
        : const <String, dynamic>{};
    final revocation = raw['revocation'];
    if (revocation != null &&
        (revocation is! Map || revocation['reason'] is! String)) {
      bad();
    }
    return StationCalibration(
      stationAlias: alias,
      status: status,
      signedCertificate: raw['artifact'],
      certificate: CalibrationCertificate(
        cid: cid,
        artifactId: artifactId,
        issuerId: issuerId,
        issuedAt: date(raw['issuedAt']),
        expiresAt: date(raw['expiresAt']),
        ownerAddress: raw['ownerAddress'] is String
            ? raw['ownerAddress'] as String
            : null,
        sensor: text(details['sensor']),
        method: text(details['method']),
        reference: text(details['reference']),
        notes: text(details['notes']),
        revocation: revocation is Map
            ? CalibrationRevocation(
                reason: revocation['reason'] as String,
                revokedAt: date(revocation['revokedAt']),
              )
            : null,
      ),
    );
  }
}

final RegExp stationAliasFormat = RegExp(r'^st_[0-9a-f]{12}$');

/// The public edge admits only the alias form, and a raw station id can carry
/// a personal name, so a raw id is hashed on this device and never sent.
String calibrationAliasFor(String stationId) {
  final clean = stationId.trim();
  return stationAliasFormat.hasMatch(clean) ? clean : stationAliasOf(clean);
}

final stationCalibrationRepositoryProvider =
    Provider<StationCalibrationRepository>(
      (ref) => StationCalibrationRepository(ref.watch(apiClientProvider).dio),
    );

class StationCalibrationRepository {
  StationCalibrationRepository(this._dio);

  final Dio _dio;

  /// `GET /calibration-certificates/station/st_<12hex>`. A 404 means the
  /// feature is off on this network ([NotAvailableFailure]).
  Future<Either<Failure, StationCalibration>> forStation(
    String stationId,
  ) async {
    try {
      final response = await _dio.get(
        ApiConstants.calibrationCertificate(calibrationAliasFor(stationId)),
      );
      return Right(StationCalibration.fromJson(response.data));
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == null) return const Left(NetworkFailure());
      if (status == 404) {
        return const Left(
          NotAvailableFailure(
            'Calibration certificates are not switched on for this network.',
            statusCode: 404,
          ),
        );
      }
      return Left(
        ServerFailure(
          'Calibration status is not available right now.',
          statusCode: status,
        ),
      );
    } on FormatException catch (error) {
      return Left(ServerFailure(error.message));
    }
  }
}

final stationCalibrationProvider = FutureProvider.autoDispose
    .family<Either<Failure, StationCalibration>, String>(
      (ref, stationId) =>
          ref.watch(stationCalibrationRepositoryProvider).forStation(stationId),
    );
