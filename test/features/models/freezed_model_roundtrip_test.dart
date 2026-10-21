import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/achievement_model.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/alert_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';

void main() {
  test('AlertModel JSON roundtrip', () {
    const model = AlertModel(
      id: 'alert-1',
      type: 'Storm',
      severity: 'severe',
      location: 'SF',
      timestamp: '2026-03-10T00:00:00Z',
      description: 'Heavy rain',
    );

    expect(AlertModel.fromJson(model.toJson()), model);
  });

  test('ForecastModel JSON roundtrip', () {
    const model = ForecastModel(
      temperature: 18.5,
      humidity: 60,
      pressure: 1013,
      windSpeed: 6.2,
      windDirection: 'NW',
      precipitation: 0.4,
      aqi: 55,
      wildfireRisk: 0.1,
      location: 'SF',
      timestamp: '2026-03-10T00:00:00Z',
    );

    expect(ForecastModel.fromJson(model.toJson()), model);
  });

  test('ForecastModel preserves an absent station sensor as null', () {
    final model = ForecastModel.fromJson({
      'temperature': 18.5,
      'humidity': 60,
      'pressure': 1013,
      'windSpeed': null,
      'precipitation': null,
      'location': 'station-without-anemometer',
      'timestamp': '2026-07-29T00:00:00Z',
    });

    expect(model.windSpeed, isNull);
    expect(model.precipitation, isNull);
  });

  test('AchievementModel JSON roundtrip', () {
    const model = AchievementModel(
      id: 'ach-1',
      name: 'First Reading',
      description: 'Submit first reading',
      tier: 'bronze',
      progress: 1,
      earned: true,
      earnedAt: '2026-03-10T00:00:00Z',
    );

    expect(AchievementModel.fromJson(model.toJson()), model);
  });

  test('ProposalModel JSON roundtrip', () {
    const model = ProposalModel(
      id: 'prop-1',
      title: 'Upgrade',
      description: 'Protocol upgrade',
      proposalType: 'economic',
      status: 'active',
      votesFor: 12,
      votesAgainst: 3,
      votesAbstain: 1,
    );

    expect(ProposalModel.fromJson(model.toJson()), model);
  });

  test('SensorReadingModel JSON roundtrip', () {
    final model = SensorReadingModel(
      id: 1,
      latitude: 37.775,
      longitude: -122.419,
      pressureHpa: 1010.5,
      timestamp: DateTime.utc(2026, 3, 10),
      synced: true,
    );

    expect(SensorReadingModel.fromJson(model.toJson()), model);
  });

  test('WalletModel JSON roundtrip', () {
    const model = WalletModel(
      address: 'wrf1wallet',
      balance: '42.0',
      transactions: 3,
      pendingTransactions: 1,
      dataSubmissions: 4,
    );

    expect(WalletModel.fromJson(model.toJson()), model);
  });

  test('TransactionModel JSON roundtrip', () {
    const model = TransactionModel(
      hash: '0xabc',
      blockNumber: 7,
      timestamp: '2026-03-10T00:00:00Z',
      from: 'wrf1from',
      to: 'wrf1to',
      value: '5.5',
      fee: '0.01',
      memo: 'hello',
      status: 'pending',
      type: 'reward',
      direction: 'incoming',
    );

    expect(TransactionModel.fromJson(model.toJson()), model);
  });
}
