import 'package:freezed_annotation/freezed_annotation.dart';

part 'transaction_model.freezed.dart';
part 'transaction_model.g.dart';

@Freezed()
sealed class TransactionModel with _$TransactionModel {
  const factory TransactionModel({
    required String hash,
    String? eventId,
    String? settlement,
    @Default(0) int blockNumber,

    /// Null when the backend did not report a time (the B3 core4 history
    /// window carries none).
    String? timestamp,
    required String from,

    /// Null when the backend did not report a recipient.
    String? to,

    /// Null when the backend did not report an amount. Never defaulted.
    String? value,
    @Default('0') String fee,
    @Default('') String memo,

    /// Null when the backend did not report a status. Never defaulted.
    String? status,
    @Default('transfer') String type,

    /// 'incoming', 'outgoing', 'self' or 'unknown'. Never assumed.
    @Default('unknown') String direction,
  }) = _TransactionModel;

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      _$TransactionModelFromJson(json);
}
