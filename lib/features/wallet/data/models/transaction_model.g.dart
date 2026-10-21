// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TransactionModel _$TransactionModelFromJson(Map<String, dynamic> json) =>
    _TransactionModel(
      hash: json['hash'] as String,
      eventId: json['eventId'] as String?,
      settlement: json['settlement'] as String?,
      blockNumber: (json['blockNumber'] as num?)?.toInt() ?? 0,
      timestamp: json['timestamp'] as String?,
      from: json['from'] as String,
      to: json['to'] as String?,
      value: json['value'] as String?,
      fee: json['fee'] as String? ?? '0',
      memo: json['memo'] as String? ?? '',
      status: json['status'] as String?,
      type: json['type'] as String? ?? 'transfer',
      direction: json['direction'] as String? ?? 'unknown',
    );

Map<String, dynamic> _$TransactionModelToJson(_TransactionModel instance) =>
    <String, dynamic>{
      'hash': instance.hash,
      'eventId': instance.eventId,
      'settlement': instance.settlement,
      'blockNumber': instance.blockNumber,
      'timestamp': instance.timestamp,
      'from': instance.from,
      'to': instance.to,
      'value': instance.value,
      'fee': instance.fee,
      'memo': instance.memo,
      'status': instance.status,
      'type': instance.type,
      'direction': instance.direction,
    };
