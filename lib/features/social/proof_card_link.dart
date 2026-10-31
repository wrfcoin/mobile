import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/api_constants.dart';
import '../../services/api/api_client.dart';

/// The public web page that shows one station reading and the block it landed
/// in (frontend `/proof/<commit id>[?h=<height>]`, backend#229).
const String proofCardWebOrigin = 'https://wrfcoin.com';

final RegExp _commitIdPattern = RegExp(r'^[0-9a-f]{64}$');
const int _maxHeight = 999999999999; // the edge admits h = 1..12 digits

/// The share link for a reading, or null when [commitId] is not a core4
/// commit id. [height] is added as `?h=` only when it is a real block height;
/// without it the page still opens (the server finds the block itself).
Uri? proofCardPageUri(String? commitId, {int? height}) {
  if (commitId == null || !_commitIdPattern.hasMatch(commitId)) return null;
  final base = Uri.parse('$proofCardWebOrigin/proof/$commitId');
  if (height == null || height < 1 || height > _maxHeight) return base;
  return base.replace(queryParameters: {'h': '$height'});
}

typedef ProofLinkShareLauncher = Future<void> Function(String text);

final proofCardLinkServiceProvider = Provider<ProofCardLinkService>((ref) {
  return ProofCardLinkService(ref.watch(apiClientProvider).dio);
});

/// Builds and shares the proof card link for the phone's latest accepted
/// reading.
class ProofCardLinkService {
  ProofCardLinkService(this._dio, {ProofLinkShareLauncher? shareLauncher})
    : _share = shareLauncher ?? _defaultShare;

  final Dio _dio;
  final ProofLinkShareLauncher _share;

  /// The link for [commitId], with the block height when the public proof
  /// card read already places the reading in a block. Any failure (the read
  /// is switched off, busy, the node did not answer, the reveal is not in a
  /// block yet) gives the link without a height; it never invents one.
  Future<Uri?> resolve(String commitId) async {
    final bare = proofCardPageUri(commitId);
    if (bare == null) return null;
    try {
      final response = await _dio.get(ApiConstants.proofCard(commitId));
      final data = response.data;
      if (data is Map && data['commitId'] == commitId) {
        final inclusion = data['inclusion'];
        if (inclusion is Map && inclusion['status'] == 'included') {
          final block = inclusion['block'];
          final height = block is Map ? block['height'] : null;
          if (height is int) return proofCardPageUri(commitId, height: height);
        }
      }
    } on DioException {
      // Fall through to the bare link.
    }
    return bare;
  }

  /// Opens the share sheet with the link. Returns the link that was shared,
  /// or null when [commitId] is not a commit id (nothing is shared).
  Future<Uri?> share(String commitId) async {
    final uri = await resolve(commitId);
    if (uri == null) return null;
    await _share('My weather station reading on the WRFCoin testnet: $uri');
    return uri;
  }

  static Future<void> _defaultShare(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
