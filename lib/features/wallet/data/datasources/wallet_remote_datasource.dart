import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../collector/data/models/station_owner_models.dart'
    show addressRawHex;
import '../../../../services/api/api_client.dart';
import '../../../../services/crypto/signed_transfer.dart';
import '../../../../services/crypto/wallet_setup_service.dart';
import '../models/transaction_model.dart';
import '../models/transaction_page.dart';
import '../models/wallet_model.dart';

final walletRemoteDataSourceProvider = Provider<WalletRemoteDataSource>((ref) {
  return WalletRemoteDataSource(ref.watch(apiClientProvider).dio);
});

final RegExp _launchAddress = RegExp(r'^0x[0-9a-f]{40}$');

class WalletRemoteDataSource {
  final Dio _dio;
  final TransferSigningDomain _signingDomain;
  final WalletSetupService _walletSetup = WalletSetupService();

  WalletRemoteDataSource(
    this._dio, {
    this._signingDomain = TransferSigningDomain.configured,
  });

  /// Balance and total earned from the public read
  /// `GET /public/balance/0x<40 hex>` (backend#30, #34).
  ///
  /// The answer is `{ address, balance, height, earned }`: balance and earned
  /// are integer base-unit strings, `earned` may be null. A 404 means public
  /// reads are switched off and a 429 means the API is busy; both return a
  /// wallet with no balance rather than a stand-in zero. Any other failure is
  /// thrown for the repository to map.
  Future<WalletModel> getWallet(String address) async {
    final rawHex = addressRawHex(address);
    final chainAddress = '0x$rawHex';
    WalletModel withoutBalance(BalanceAvailability availability) => WalletModel(
      address: address,
      balance: null,
      balanceAvailability: availability,
    );

    final Response<dynamic> response;
    try {
      response = await _dio.get(ApiConstants.publicBalance(rawHex));
    } on DioException catch (e) {
      switch (e.response?.statusCode) {
        case 404:
          return withoutBalance(BalanceAvailability.unavailable);
        case 429:
          return withoutBalance(BalanceAvailability.busy);
      }
      rethrow;
    }

    final payload = response.data;
    if (payload is! Map) {
      return withoutBalance(BalanceAvailability.unavailable);
    }
    final reported = payload['address'];
    final balance = _chainRewardAmount(payload['balance']);
    // An answer for a different address, or with no usable balance, is
    // not this wallet's balance.
    if (reported is! String ||
        reported.toLowerCase() != chainAddress ||
        balance == null) {
      return withoutBalance(BalanceAvailability.unavailable);
    }
    final height = payload['height'];
    return WalletModel(
      address: address,
      balance: balance,
      height: height is int && height >= 0 ? height : null,
      earnedBalanceTotal: _chainRewardAmount(payload['earned']),
    );
  }

  /// One page of history for [address], starting at [offset].
  ///
  /// Only what the backend reports is kept: a missing amount, recipient,
  /// status or timestamp stays null. Schema v2 uses explicit directions and
  /// decimal strings; only legacy history derives direction from the sender.
  Future<TransactionPage> getTransactions(
    String address, {
    int offset = 0,
    int limit = 20,
    String? creditAfter,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get(
      ApiConstants.walletTransactions(address, offset: offset, limit: limit),
      queryParameters: {'creditLimit': 100, 'creditAfter': ?creditAfter},
      cancelToken: cancelToken,
    );
    final list = _extractList(response.data);
    final meta = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};

    final version2 = meta['schemaVersion'] == 2;
    // A reward row in `items` must pass the same paid-credit gate as
    // `creditItems`, so an unpaid or malformed reward never renders; its
    // eventId also claims the reward so `creditItems` cannot repeat it.
    final itemRewardIds = <String>{};
    final items = list
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .where((e) {
          if (!version2 || !_isRewardKind(e['kind'])) return true;
          if (!_paidCredit(e, address)) return false;
          return itemRewardIds.add(e['eventId'] as String);
        })
        .map((e) => _normalizeTransaction(e, address, version2: version2))
        .map(TransactionModel.fromJson)
        .toList();

    final creditIds = <String>{};
    final credits = version2 && meta['creditItems'] is List
        ? (meta['creditItems'] as List)
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .where(
                (e) =>
                    _paidCredit(e, address) &&
                    !itemRewardIds.contains(e['eventId']) &&
                    creditIds.add(e['eventId'] as String),
              )
              .map(
                (e) => TransactionModel.fromJson(
                  _normalizeTransaction(e, address, version2: true),
                ),
              )
              .toList()
        : <TransactionModel>[];
    final complete = meta['complete'];
    return TransactionPage(
      items: items,
      credits: credits,
      creditNextCursor: version2 ? _nonEmpty(meta['creditNextCursor']) : null,
      offset: _readOptionalInt(meta['offset']) ?? offset,
      limit: _readOptionalInt(meta['limit']) ?? limit,
      complete: complete is bool ? complete : null,
      windowStartHeight: _readOptionalInt(meta['windowStartHeight']),
      totalInWindow: _readOptionalInt(meta['totalInWindow']),
    );
  }

  /// Chain account nonce for [address] from `GET /wallet/:address/nonce`.
  ///
  /// Owner-bound since backend#1199: the JWT `sub` must equal [address] or
  /// the backend answers 403.
  Future<String> getAccountNonce(String address) async {
    final response = await _dio.get(ApiConstants.walletAccountNonce(address));
    final payload = _unwrapMap(response.data);
    final nonce = payload['nonce']?.toString() ?? '';
    if (!RegExp(r'^\d+$').hasMatch(nonce)) {
      throw StateError('Backend returned no usable account nonce');
    }
    return nonce;
  }

  /// Submits a client-signed transparent transfer (backend#1197).
  ///
  /// [amountBaseUnits] is an integer base-unit string (see `wrf_units.dart`).
  /// The addresses are lowercased once and the same strings are signed and
  /// posted, because core4 hashes them as strings. The memo is not part of
  /// the signed contract and the backend does not relay it, so none is sent.
  Future<Map<String, dynamic>> sendTransaction({
    required String from,
    required String to,
    required String amountBaseUnits,
    required Ed25519TransferSigner signer,
  }) async {
    final sender = from.trim().toLowerCase();
    final recipient = to.trim().toLowerCase();
    if (!_launchAddress.hasMatch(sender) ||
        !_launchAddress.hasMatch(recipient)) {
      throw ArgumentError('from and to must be 0x-prefixed chain addresses');
    }
    final signerAddress = _walletSetup.chainAddressFromEd25519(
      signer.publicKey,
    );
    if (signerAddress != sender) {
      throw StateError('Signing key does not control the sending address');
    }

    final nonce = await getAccountNonce(sender);
    final body = await buildSignedTransferBody(
      signer: signer,
      domain: _signingDomain,
      from: sender,
      to: recipient,
      amountBaseUnits: amountBaseUnits,
      nonce: nonce,
    );
    final response = await _dio.post(
      ApiConstants.walletSend,
      data: body,
      options: Options(extra: {'noRetry': true, 'noAuthRetry': true}),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<String> generateStealthAddress(String recipientAddress) async {
    final response = await _dio.post(
      ApiConstants.walletStealthAddress,
      data: {'recipientAddress': recipientAddress},
    );
    final data = _unwrapMap(response.data);
    final stealth = data['stealthAddress']?.toString();
    if (stealth == null || stealth.isEmpty) {
      throw StateError('Backend returned no stealth address');
    }
    return stealth;
  }

  Future<Map<String, dynamic>> sendPrivateTransaction({
    required String from,
    required String to,
    required String amount,
    required String privacyLevel,
    String? memo,
  }) async {
    final response = await _dio.post(
      ApiConstants.walletSendPrivate,
      data: {
        'from': from,
        'to': to,
        'amount': amount,
        'privacyLevel': privacyLevel,
        // ignore: use_null_aware_elements
        if (memo != null) 'memo': memo,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> estimateGas({
    required String from,
    required String to,
    required String amount,
    String? memo,
  }) async {
    final response = await _dio.post(
      ApiConstants.walletEstimateGas,
      data: {
        'from': from,
        'to': to,
        'amount': amount,
        // ignore: use_null_aware_elements
        if (memo != null) 'memo': memo,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sponsorGas({
    required String walletAddress,
    required Map<String, dynamic> userOp,
  }) async {
    final response = await _dio.post(
      ApiConstants.gasSponsor,
      data: {'walletAddress': walletAddress, 'userOp': userOp},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitUserOp({
    required Map<String, dynamic> userOp,
  }) async {
    final response = await _dio.post(
      ApiConstants.submitUserOp,
      data: {'userOp': userOp},
    );
    return response.data as Map<String, dynamic>;
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

    throw StateError('Expected wallet API response to be an object.');
  }

  List<dynamic> _extractList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is! Map) return const <dynamic>[];

    final map = Map<String, dynamic>.from(payload);
    for (final key in const ['items', 'transactions', 'data']) {
      final candidate = map[key];
      if (candidate is List) return candidate;
      if (candidate is Map) {
        final nested = _extractList(candidate);
        if (nested.isNotEmpty) return nested;
      }
    }

    return const <dynamic>[];
  }

  Map<String, dynamic> _normalizeTransaction(
    Map<String, dynamic> json,
    String ownAddress, {
    bool version2 = false,
  }) {
    final from = json['from']?.toString() ?? '';
    final amount = version2
        ? json['amountBaseUnits']
        : json['value'] ?? json['amount'];
    return <String, dynamic>{
      'hash': json['hash'] ?? json['txHash'] ?? json['txId'] ?? '',
      'eventId': version2 ? _nonEmpty(json['eventId']) : null,
      'settlement': version2 ? _nonEmpty(json['settlement']) : null,
      'blockNumber': _readInt(json['blockNumber'] ?? json['blockHeight']),
      'timestamp': _nonEmpty(json['timestamp'] ?? json['createdAt']),
      'from': from,
      'to': _nonEmpty(json['to']),
      'value': version2
          ? _historyAmount(amount)
          : amount == null
          ? null
          : _normalizeAmount(amount),
      'fee': _normalizeAmount(json['fee']),
      'memo': json['memo']?.toString() ?? '',
      'status': _nonEmpty(json['status']),
      'type':
          (version2 ? json['kind']?.toString() : null) ??
          json['type']?.toString() ??
          json['tx_type']?.toString() ??
          json['token']?.toString() ??
          (version2 ? 'unknown' : 'transfer'),
      'direction': version2
          ? switch (json['direction']) {
              'received' => 'incoming',
              'sent' => 'outgoing',
              'self' => 'self',
              _ => 'unknown',
            }
          : _direction(json['direction'], from, ownAddress),
    };
  }

  static String? _historyAmount(dynamic value) {
    if (value is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,38})$').hasMatch(value)) {
      return null;
    }
    return BigInt.parse(value) <= (BigInt.one << 128) - BigInt.one
        ? value
        : null;
  }

  static bool _isRewardKind(dynamic kind) =>
      kind == 'weather_reward' || kind == 'forecast_reward';

  static bool _paidCredit(Map<String, dynamic> e, String address) {
    final amount = _historyAmount(e['amountBaseUnits']);
    final id = e['eventId'];
    final kind = e['kind'];
    final prefix = kind == 'weather_reward'
        ? 'contribution:'
        : kind == 'forecast_reward'
        ? 'forecast:'
        : null;
    return prefix != null &&
        id is String &&
        id.startsWith(prefix) &&
        id.length > prefix.length &&
        e['settlement'] == 'paid' &&
        e['direction'] == 'received' &&
        e['to'] is String &&
        _canonicalAddress(e['to'] as String) == _canonicalAddress(address) &&
        amount != null &&
        BigInt.parse(amount) > BigInt.zero;
  }

  /// The legacy backend does not send a direction, so it is derived: the wallet sent
  /// it when the sender is the wallet's own address, and otherwise it was
  /// received (the history lists only transactions touching this address).
  /// With no sender at all the direction is unknown, never assumed.
  static String _direction(dynamic explicit, String from, String ownAddress) {
    final stated = explicit?.toString();
    if (stated == 'incoming' || stated == 'outgoing') return stated!;
    if (from.trim().isEmpty) return 'unknown';
    return _canonicalAddress(from) == _canonicalAddress(ownAddress)
        ? 'outgoing'
        : 'incoming';
  }

  /// Case-insensitive, `0x`-lowercase form for comparing chain addresses.
  static String _canonicalAddress(String address) {
    final lower = address.trim().toLowerCase();
    return lower.startsWith('0x') ? lower : '0x$lower';
  }

  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static int? _readOptionalInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _normalizeAmount(dynamic value) {
    if (value == null) return '0';

    final raw = value.toString().trim().replaceAll(',', '');
    if (raw.isEmpty) return '0';

    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
    return match?.group(0) ?? '0';
  }

  String? _chainRewardAmount(dynamic value) {
    if (value is! String && value is! int) return null;
    final raw = value.toString();
    return RegExp(r'^(0|[1-9][0-9]{0,38})$').hasMatch(raw) ? raw : null;
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_normalizeAmount(value)) ?? 0;
  }
}
