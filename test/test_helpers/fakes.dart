import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:local_auth/local_auth.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/weather_nft_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/nft_repository.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/challenges/data/models/challenge_model.dart';
import 'package:wrfcoin_mobile/features/challenges/data/repositories/challenge_repository.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/achievement_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/leaderboard_entry_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/alert_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/current_conditions_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/wrf_forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_page.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/repositories/wallet_repository.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/security/screen_security_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../support/wrf_forecast_fixtures.dart';

class InMemoryKeyValueStorage implements KeyValueStorage {
  final Map<String, String?> _values = <String, String?>{};

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, String? value}) async {
    _values[key] = value;
  }
}

class TestAppPreferencesStore extends AppPreferencesStore {
  TestAppPreferencesStore([this._preferences = const AppPreferences()]);

  AppPreferences _preferences;

  @override
  Future<AppPreferences> load() async => _preferences;

  @override
  Future<void> save(AppPreferences preferences) async {
    _preferences = preferences;
  }
}

class FakeLocalAuthClient implements LocalAuthClient {
  FakeLocalAuthClient({
    this.canCheck = true,
    this.deviceSupported = true,
    this.authenticateResult = true,
    this.biometricOnlyAuthenticateResult,
    this.availableBiometrics = const [BiometricType.fingerprint],
    this.throwOnCanCheck = false,
    this.throwOnAuthenticate = false,
    this.throwOnGetAvailable = false,
  });

  final bool canCheck;
  final bool deviceSupported;
  final bool authenticateResult;
  final bool? biometricOnlyAuthenticateResult;
  final List<BiometricType> availableBiometrics;
  final bool throwOnCanCheck;
  final bool throwOnAuthenticate;
  final bool throwOnGetAvailable;
  final List<bool> authenticateBiometricOnlyCalls = <bool>[];

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    if (throwOnAuthenticate) throw Exception('authenticate failed');
    authenticateBiometricOnlyCalls.add(biometricOnly);
    if (biometricOnly && biometricOnlyAuthenticateResult != null) {
      return biometricOnlyAuthenticateResult!;
    }
    return authenticateResult;
  }

  @override
  Future<bool> canCheckBiometrics() async {
    if (throwOnCanCheck) throw Exception('canCheck failed');
    return canCheck;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (throwOnGetAvailable) throw Exception('available biometrics failed');
    return availableBiometrics;
  }

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;
}

class FakeScreenSecurityClient implements ScreenSecurityClient {
  bool protectionEnabled = false;
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enableProtection() async {
    enableCalls++;
    protectionEnabled = true;
  }

  @override
  Future<void> disableProtection() async {
    disableCalls++;
    protectionEnabled = false;
  }
}

class FakeWalletRepository implements WalletRepository {
  FakeWalletRepository({
    this.wallet,
    this.transactions = const <TransactionModel>[],
    this.sendTransactionResult,
    this.estimateGasResult,
    this.sponsorGasResult,
    this.submitUserOpResult,
  });

  final WalletModel? wallet;
  final List<TransactionModel> transactions;
  final Either<Failure, Map<String, dynamic>>? sendTransactionResult;
  final Either<Failure, Map<String, dynamic>>? estimateGasResult;
  final Either<Failure, Map<String, dynamic>>? sponsorGasResult;
  final Either<Failure, Map<String, dynamic>>? submitUserOpResult;
  int sendCalls = 0;
  final List<String> sentAmountBaseUnits = <String>[];
  final List<String> sentTo = <String>[];
  final List<String> estimateGasAmounts = <String>[];
  int sponsorGasCalls = 0;
  int submitUserOpCalls = 0;

  @override
  Future<Either<Failure, Map<String, dynamic>>> estimateGas({
    required String from,
    required String to,
    required String amount,
    String? memo,
  }) async {
    estimateGasAmounts.add(amount);
    return estimateGasResult ??
        const Right(<String, dynamic>{'estimatedFee': '0.001'});
  }

  @override
  Future<Either<Failure, TransactionPage>> getTransactions(
    String address, {
    int offset = 0,
    int limit = 20,
    String? creditAfter,
    CancelToken? cancelToken,
  }) async {
    final slice = transactions.skip(offset).take(limit).toList();
    return Right(
      TransactionPage(
        items: slice,
        offset: offset,
        limit: limit,
        totalInWindow: transactions.length,
      ),
    );
  }

  @override
  Future<Either<Failure, WalletModel>> getWallet(String address) async {
    return Right(
      wallet ??
          const WalletModel(
            address: 'wrf1testwallet0000000000',
            balance: '4200000000', // 42 WRF in base units
            transactions: 2,
          ),
    );
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> sendTransaction({
    required String from,
    required String to,
    required String amountBaseUnits,
    required Ed25519TransferSigner signer,
  }) async {
    sendCalls++;
    sentAmountBaseUnits.add(amountBaseUnits);
    sentTo.add(to);
    return sendTransactionResult ??
        const Right(<String, dynamic>{'hash': '0xabc'});
  }

  @override
  Future<Either<Failure, String>> generateStealthAddress(
    String recipientAddress,
  ) async {
    return Right('wrf1stealth${recipientAddress.substring(0, 8)}test');
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> sendPrivateTransaction({
    required String from,
    required String to,
    required String amount,
    required String privacyLevel,
    String? memo,
  }) async {
    sendCalls++;
    return sendTransactionResult ??
        const Right(<String, dynamic>{'hash': '0xprivate'});
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> sponsorGas({
    required String walletAddress,
    required Map<String, dynamic> userOp,
  }) async {
    sponsorGasCalls++;
    return sponsorGasResult ??
        const Right(<String, dynamic>{'paymasterAndData': '0xpaymaster'});
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> submitUserOp({
    required Map<String, dynamic> userOp,
  }) async {
    submitUserOpCalls++;
    return submitUserOpResult ??
        const Right(<String, dynamic>{'userOpHash': '0x1'});
  }
}

class FakeWalletSecureStorage extends WalletSecureStorage {
  FakeWalletSecureStorage({
    this.backupConfirmed = true,
    this.isSocial = false,
    List<AddressBookEntry>? addressBook,
  }) : _addressBook = addressBook ?? <AddressBookEntry>[];

  final List<AddressBookEntry> _addressBook;
  bool backupConfirmed;
  bool isSocial;
  int clearWalletDataCalls = 0;

  @override
  Future<void> addAddressBookEntry(AddressBookEntry entry) async {
    _addressBook.insert(0, entry);
  }

  @override
  Future<List<AddressBookEntry>> getAddressBook() async => _addressBook;

  @override
  Future<void> clearWalletData() async {
    clearWalletDataCalls++;
    backupConfirmed = false;
    isSocial = false;
    _addressBook.clear();
  }

  @override
  Future<bool> getBackupConfirmed() async => backupConfirmed;

  @override
  Future<bool> getIsSocial() async => isSocial;

  @override
  Future<void> setBackupConfirmed(bool confirmed) async {
    backupConfirmed = confirmed;
  }

  @override
  Future<void> setIsSocial(bool social) async {
    isSocial = social;
  }
}

class FakeChallengeRepository implements ChallengeRepository {
  FakeChallengeRepository({
    List<ChallengeModel>? challenges,
    this.createFailure,
    this.joinFailure,
  }) : _challenges = challenges ?? const <ChallengeModel>[];

  List<ChallengeModel> _challenges;
  final Failure? createFailure;
  final Failure? joinFailure;

  @override
  Future<Either<Failure, List<ChallengeModel>>> createChallenge({
    required String userId,
    required String displayName,
    required CreateChallengeInput input,
  }) async {
    if (createFailure != null) return Left(createFailure!);

    final now = DateTime(2026, 4, 9, 12);
    _challenges = <ChallengeModel>[
      ChallengeModel(
        id: 'created-${_challenges.length}',
        title: input.title.trim(),
        description: input.description.trim().isEmpty
            ? 'First to ${input.targetScore} readings.'
            : input.description.trim(),
        format: input.format,
        status: ChallengeStatus.pending,
        inviteCode: 'TEST-42',
        targetScore: input.targetScore,
        startsAt: now,
        endsAt: now.add(input.duration),
        lastUpdatedAt: now,
        participants: <ChallengeParticipant>[
          ChallengeParticipant(
            id: userId,
            name: displayName,
            score: 0,
            isCurrentUser: true,
            teamName: input.format == ChallengeFormat.team ? 'North Front' : '',
            subtitle: 'Host',
          ),
        ],
      ),
      ..._challenges,
    ];
    return Right(_snapshot());
  }

  @override
  Future<Either<Failure, List<ChallengeModel>>> getChallenges({
    required String userId,
    required String displayName,
  }) async {
    if (_challenges.isEmpty) {
      _challenges = <ChallengeModel>[
        ChallengeModel(
          id: 'sample-live',
          title: 'Sample Sprint',
          description: 'Fast-moving reading race.',
          format: ChallengeFormat.headToHead,
          status: ChallengeStatus.live,
          inviteCode: 'SAMPLE-7',
          targetScore: 25,
          startsAt: DateTime(2026, 4, 9, 8),
          endsAt: DateTime(2026, 4, 12, 8),
          lastUpdatedAt: DateTime(2026, 4, 9, 12),
          participants: <ChallengeParticipant>[
            ChallengeParticipant(
              id: userId,
              name: displayName,
              score: 11,
              isCurrentUser: true,
              subtitle: 'You',
            ),
            const ChallengeParticipant(
              id: 'opponent',
              name: 'Maya',
              score: 10,
              subtitle: 'Rival',
            ),
          ],
        ),
        ChallengeModel(
          id: 'invite-open',
          title: 'Referral Race',
          description: 'Join this challenge with the sample code.',
          format: ChallengeFormat.headToHead,
          status: ChallengeStatus.pending,
          inviteCode: 'RADAR-21',
          targetScore: 21,
          startsAt: DateTime(2026, 4, 10, 8),
          endsAt: DateTime(2026, 4, 13, 8),
          lastUpdatedAt: DateTime(2026, 4, 9, 12),
          participants: <ChallengeParticipant>[
            ChallengeParticipant(
              id: 'host',
              name: 'Jess',
              score: 0,
              subtitle: 'Host',
            ),
          ],
        ),
      ];
    }
    return Right(_snapshot());
  }

  @override
  Future<Either<Failure, List<ChallengeModel>>> joinChallengeByReferralCode({
    required String userId,
    required String displayName,
    required String referralCode,
  }) async {
    if (joinFailure != null) return Left(joinFailure!);

    final index = _challenges.indexWhere(
      (challenge) => challenge.inviteCode == referralCode.trim().toUpperCase(),
    );
    if (index < 0) {
      return const Left(
        ValidationFailure('No challenge matched that referral code.'),
      );
    }

    final challenge = _challenges[index];
    _challenges[index] = challenge.copyWith(
      status: ChallengeStatus.live,
      participants: <ChallengeParticipant>[
        ...challenge.participants,
        ChallengeParticipant(
          id: userId,
          name: displayName,
          score: 0,
          isCurrentUser: true,
          subtitle: 'Joined',
        ),
      ],
      lastUpdatedAt: DateTime(2026, 4, 9, 12, 5),
    );

    return Right(_snapshot());
  }

  @override
  Future<Either<Failure, List<ChallengeModel>>> registerCollection({
    required String userId,
    required int delta,
  }) async {
    _challenges = _challenges
        .map((challenge) {
          final participants = challenge.participants
              .map((participant) {
                if (participant.id == userId) {
                  return participant.copyWith(score: participant.score + delta);
                }
                return participant;
              })
              .toList(growable: false);
          return challenge.copyWith(participants: participants);
        })
        .toList(growable: false);
    return Right(_snapshot());
  }

  List<ChallengeModel> _snapshot() {
    return _challenges
        .map(
          (challenge) => challenge.copyWith(
            participants: challenge.participants
                .map((participant) => participant.copyWith())
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }
}

class FakeGovernanceRepository extends GovernanceRepository {
  FakeGovernanceRepository({
    this.proposals = const <ProposalModel>[],
    this.treasury = const <String, dynamic>{'balance': '1000'},
  }) : super(Dio());

  final List<ProposalModel> proposals;
  final Map<String, dynamic> treasury;

  @override
  Future<Either<Failure, List<ProposalModel>>> getProposals() async {
    return Right(proposals);
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getTreasuryInfo() async {
    return Right(treasury);
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> vote({
    required String proposalId,
    required String voteType,
    String? reason,
  }) async {
    return const Right(<String, dynamic>{'ok': true});
  }
}

class FakeWeatherRepository extends WeatherRepository {
  FakeWeatherRepository({
    this.alerts = const <AlertModel>[],
    this.forecast = const ForecastModel(
      temperature: 20,
      humidity: 50,
      pressure: 1012,
      windSpeed: 5,
      precipitation: 0,
      aqi: 42,
      location: 'Local',
      timestamp: '2026-03-10T00:00:00Z',
    ),
    this.wrfForecast,
    this.current,
  }) : super(Dio());

  final List<AlertModel> alerts;
  final ForecastModel forecast;

  /// Current conditions (mobile#332); null answers "not available" without
  /// touching the network.
  final CurrentConditions? current;

  /// WRF forecast result; defaults to the simulated test fixture.
  final Either<Failure, WrfForecastModel> Function(CoarseLocation location)?
  wrfForecast;

  @override
  Future<Either<Failure, List<AlertModel>>> getActiveAlerts(
    CoarseLocation location,
  ) async {
    return Right(alerts);
  }

  @override
  Future<Either<Failure, ForecastModel>> getForecast(
    CoarseLocation location,
  ) async {
    return Right(forecast);
  }

  @override
  Future<Either<Failure, CurrentConditions>> getCurrentConditions(
    CoarseLocation location,
  ) async {
    final current = this.current;
    return current == null
        ? const Left(NotAvailableFailure('No current conditions.'))
        : Right(current);
  }

  @override
  Future<Either<Failure, WrfForecastModel>> getWrfForecast(
    CoarseLocation location,
  ) async {
    return wrfForecast?.call(location) ??
        Right(wrfForecastSimulationStub(location.pathSegment));
  }
}

/// Resolves to a fixed [location] (or none) without touching Geolocator.
class FixedWeatherLocationResolver extends WeatherLocationResolver {
  const FixedWeatherLocationResolver(this.location);

  final CoarseLocation? location;

  @override
  Future<WeatherLocationResult> resolve() async => location == null
      ? const WeatherLocationResult.unavailable(
          LocationUnavailableReason.permissionDenied,
        )
      : WeatherLocationResult.located(location!);
}

class FakeGamificationRepository extends GamificationRepository {
  FakeGamificationRepository({
    this.achievements = const <AchievementModel>[],
    this.leaderboard = const <LeaderboardEntry>[],
  }) : super(Dio());

  final List<AchievementModel> achievements;
  final List<LeaderboardEntry> leaderboard;

  @override
  Future<Either<Failure, List<AchievementModel>>> getAchievements(
    String userId,
  ) async {
    return Right(achievements);
  }

  @override
  Future<Either<Failure, List<LeaderboardEntry>>> getLeaderboard() async {
    return Right(leaderboard);
  }
}

/// SyncWorker that returns an empty connectivity stream so integration tests
/// never block on [pumpAndSettle] waiting for a pending stream listener.
class FakeSyncWorker extends SyncWorker {
  FakeSyncWorker() : super();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  Future<SyncRunResult> syncPendingReadings({
    bool includeIdempotencyKey = false,
  }) async {
    return const SyncRunResult(
      acceptedCount: 0,
      failedCount: 0,
      pendingCount: 0,
      reason: SyncRunReason.idle,
    );
  }
}

class FakeNftRepository extends NftRepository {
  FakeNftRepository({this.portfolioResult, this.claimResult})
    : super(Dio(BaseOptions(baseUrl: 'http://localhost')));

  Either<Failure, List<WeatherNftModel>>? portfolioResult;
  Either<Failure, WeatherNftModel>? claimResult;
  int getPortfolioCalls = 0;
  int claimNftCalls = 0;

  @override
  Future<Either<Failure, List<WeatherNftModel>>> getPortfolio(
    String userId,
  ) async {
    getPortfolioCalls++;
    return portfolioResult ?? const Right(<WeatherNftModel>[]);
  }

  @override
  Future<Either<Failure, WeatherNftModel>> claimNft(
    String userId,
    String nftId,
  ) async {
    claimNftCalls++;
    if (claimResult != null) return claimResult!;
    return portfolioResult
            ?.toOption()
            .toNullable()
            ?.where((n) => n.id == nftId)
            .map(
              (n) => WeatherNftModel(
                id: n.id,
                type: n.type,
                tier: n.tier,
                rarity: n.rarity,
                status: NftStatus.owned,
                name: n.name,
                description: n.description,
                earnedAt: '2026-04-20T00:00:00Z',
              ),
            )
            .map<Either<Failure, WeatherNftModel>>(Right.new)
            .firstOrNull ??
        Left(const ServerFailure('nft not found'));
  }
}

class FakeBatteryMonitor extends BatteryMonitor {
  FakeBatteryMonitor({this.batteryLevel = 100});
  final int batteryLevel;

  @override
  Future<int> getBatteryLevel() async => batteryLevel;

  @override
  Future<bool> shouldPauseCollection({int threshold = 15}) async =>
      batteryLevel < threshold;
}

class FakeCollectorRepository extends CollectorRepository {
  FakeCollectorRepository({
    this.reading,
    this.pendingCount = 0,
    this.syncMetadata,
  }) : super(
         sensorDataSource: SensorDataSource(LocationService()),
         batteryMonitor: BatteryMonitor(),
         apiClient: ApiClient(dio: Dio()),
         db: FakeCollectorLocalStore()..syncMetadata = syncMetadata,
       );

  final SensorReadingModel? reading;
  final int pendingCount;
  final SyncMetadataEntry? syncMetadata;

  @override
  Future<CollectReadingResult> collectReading({
    int batteryThreshold = 15,
    int baseIntervalMinutes = 15,
    bool force = false,
  }) async {
    if (reading == null) {
      return const CollectReadingResult.failure(
        CollectReadingFailureReason.barometerUnavailable,
      );
    }
    return CollectReadingResult.success(reading);
  }

  @override
  Future<int> getUnsyncedCount() async => pendingCount;
}

class FakeCollectorLocalStore implements CollectorLocalStore {
  FakeCollectorLocalStore({this.pendingCount = 0, this.latestReading});

  int pendingCount;
  final List<int> syncedIds = <int>[];
  int insertCalls = 0;
  SyncMetadataEntry? syncMetadata;
  SensorReading? latestReading;

  @override
  Future<int> insertReading(SensorReadingsCompanion reading) async {
    insertCalls++;
    pendingCount++;
    return insertCalls;
  }

  @override
  Future<SensorReading?> getLatestReading() async => latestReading;

  @override
  Future<List<SensorReading>> getReadingHistory({int limit = 5000}) async =>
      latestReading == null ? const [] : [latestReading!];

  @override
  Future<void> markReadingsSynced(List<int> ids) async {
    syncedIds.addAll(ids);
    pendingCount -= ids.length;
  }

  @override
  Future<int> getPendingSyncCount() async => pendingCount;

  @override
  Future<void> clearUnsyncedReadings() async {
    pendingCount = 0;
  }

  @override
  Future<void> clearPendingImages() async {}

  @override
  Future<void> clearSyncMetadata(String syncTableName) async {
    syncMetadata = null;
  }

  @override
  Future<SyncMetadataEntry?> getSyncMetadata(String syncTableName) async {
    return syncMetadata;
  }

  @override
  Future<void> upsertSyncMetadata({
    required String syncTableName,
    required int pendingCount,
    DateTime? lastSyncAt,
    DateTime? lastSyncAttemptAt,
    String? lastSyncError,
  }) async {
    this.pendingCount = pendingCount;
    syncMetadata = SyncMetadataEntry(
      id: syncMetadata?.id ?? 1,
      syncTableName: syncTableName,
      pendingCount: pendingCount,
      lastSyncAt: lastSyncAt ?? syncMetadata?.lastSyncAt,
      lastSyncAttemptAt: lastSyncAttemptAt ?? syncMetadata?.lastSyncAttemptAt,
      lastSyncError: lastSyncError,
    );
  }
}
