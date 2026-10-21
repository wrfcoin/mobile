import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/wear/domain/watch_companion_contract.dart';

typedef SnapshotPayload = Map<String, Object?>;

abstract class WatchCompanionTransport {
  Future<int> publish(SnapshotPayload payload);
}

abstract class WatchCompanionGateway {
  Future<int> publishFromReading(
    SensorReadingModel reading, {
    required String platform,
    bool? passiveCollectionEnabled,
    String? note,
  });
}

class WatchCompanionGatewayOnTransport implements WatchCompanionGateway {
  WatchCompanionGatewayOnTransport(
    this._transport, [
    List<WatchCompanionContract>? captured,
  ]) : _captured = captured;

  final WatchCompanionTransport _transport;
  final List<WatchCompanionContract>? _captured;

  List<WatchCompanionContract>? get captured => _captured;

  @override
  Future<int> publishFromReading(
    SensorReadingModel reading, {
    required String platform,
    bool? passiveCollectionEnabled,
    String? note,
  }) async {
    final payload = WatchCompanionContract.fromReading(
      reading,
      platform: platform,
      passiveCollectionEnabled: passiveCollectionEnabled,
      note: note,
    );
    _captured?.add(payload);
    return _transport.publish(payload.toMap());
  }
}

class NoopWatchCompanionTransport implements WatchCompanionTransport {
  @override
  Future<int> publish(SnapshotPayload payload) async => 0;
}

class InMemoryWatchCompanionTransport implements WatchCompanionTransport {
  InMemoryWatchCompanionTransport() : _sent = <SnapshotPayload>[];

  final List<SnapshotPayload> _sent;

  List<SnapshotPayload> get sent => List.unmodifiable(_sent);

  @override
  Future<int> publish(SnapshotPayload payload) async {
    _sent.add(Map<String, Object?>.from(payload));
    return _sent.length;
  }
}
