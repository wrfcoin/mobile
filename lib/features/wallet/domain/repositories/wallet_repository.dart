import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../services/crypto/signed_transfer.dart';
import '../../data/models/transfer_fee.dart';
import '../../data/models/wallet_model.dart';
import '../../data/models/transaction_page.dart';

abstract class WalletRepository {
  Future<Either<Failure, WalletModel>> getWallet(String address);

  Future<Either<Failure, TransactionPage>> getTransactions(
    String address, {
    int offset = 0,
    int limit = 20,
    String? creditAfter,
    CancelToken? cancelToken,
  });

  Future<Either<Failure, Map<String, dynamic>>> sendTransaction({
    required String from,
    required String to,
    required String amountBaseUnits,
    required Ed25519TransferSigner signer,

    /// Runs with the signed nonce, right before the post.
    Future<void> Function(String nonce)? onBeforeSubmit,
  });

  /// The account's nonce as committed on chain.
  Future<Either<Failure, String>> getAccountNonce(String address);

  /// The block holding [hash] in the wallet's chain history, or null if it
  /// isn't there.
  Future<Either<Failure, int?>> findIncludedBlock(String address, String hash);

  Future<Either<Failure, String>> generateStealthAddress(
    String recipientAddress,
  );

  Future<Either<Failure, Map<String, dynamic>>> sendPrivateTransaction({
    required String from,
    required String to,
    required String amount,
    required String privacyLevel,
    String? memo,
  });

  Future<Either<Failure, TransferFeeQuote>> getTransferFee(String address);

  Future<Either<Failure, Map<String, dynamic>>> sponsorGas({
    required String walletAddress,
    required Map<String, dynamic> userOp,
  });

  Future<Either<Failure, Map<String, dynamic>>> submitUserOp({
    required Map<String, dynamic> userOp,
  });
}
