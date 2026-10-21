import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Fetches weather observation payloads from decentralized storage gateways.
///
/// The client tries IPFS gateways first and then falls back to Arweave
/// gateways if the content is unavailable or a gateway is unhealthy.
class StorageGatewayClient {
  StorageGatewayClient({
    Dio? dio,
    List<String> ipfsGateways = const ['https://ipfs.io'],
    List<String> arweaveGateways = const ['https://arweave.net'],
    Duration timeout = const Duration(seconds: 15),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: timeout,
               receiveTimeout: timeout,
               responseType: ResponseType.bytes,
             ),
           ),
       _gateways = [
         for (final gateway in ipfsGateways)
           _StorageGatewayEndpoint(
             provider: _StorageGatewayProvider.ipfs,
             baseUri: Uri.parse(gateway),
           ),
         for (final gateway in arweaveGateways)
           _StorageGatewayEndpoint(
             provider: _StorageGatewayProvider.arweave,
             baseUri: Uri.parse(gateway),
           ),
       ];

  final Dio _dio;
  final List<_StorageGatewayEndpoint> _gateways;

  /// Fetch the raw payload bytes for a weather observation CID.
  Future<Uint8List> fetchWeatherObservation(String cid) async {
    final normalizedCid = cid.trim();
    if (normalizedCid.isEmpty) {
      throw ArgumentError.value(cid, 'cid', 'must not be empty');
    }

    Object? lastError;

    for (final gateway in _gateways) {
      final uri = gateway.buildObservationUri(normalizedCid);
      try {
        final response = await _dio.getUri(
          uri,
          options: Options(responseType: ResponseType.bytes),
        );
        return _normalizeBytes(response.data);
      } on DioException catch (error) {
        lastError = error;
      }
    }

    throw StorageGatewayException(
      'Unable to fetch weather observation $normalizedCid from IPFS/Arweave gateways',
      cause: lastError,
    );
  }

  Uint8List _normalizeBytes(dynamic data) {
    if (data is Uint8List) {
      return data;
    }
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }
    if (data is String) {
      return Uint8List.fromList(utf8.encode(data));
    }

    throw StorageGatewayException(
      'Unsupported response payload type: ${data.runtimeType}',
    );
  }
}

enum _StorageGatewayProvider { ipfs, arweave }

class _StorageGatewayEndpoint {
  const _StorageGatewayEndpoint({
    required this.provider,
    required this.baseUri,
  });

  final _StorageGatewayProvider provider;
  final Uri baseUri;

  Uri buildObservationUri(String cid) {
    final encodedCid = Uri.encodeComponent(cid);
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final suffix = provider == _StorageGatewayProvider.ipfs
        ? '/ipfs/$encodedCid'
        : '/$encodedCid';

    return baseUri.replace(path: '$basePath$suffix');
  }
}

class StorageGatewayException implements Exception {
  StorageGatewayException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return 'StorageGatewayException: $message';
    }
    return 'StorageGatewayException: $message (cause: $cause)';
  }
}
