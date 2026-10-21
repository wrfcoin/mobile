import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/weather_nft_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/nft_repository.dart';

void main() {
  late Dio dio;
  late NftRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    repository = NftRepository(dio);
  });

  void stubResponse(dynamic data, {int statusCode = 200}) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: statusCode,
              data: data,
            ),
          );
        },
      ),
    );
  }

  void stubError({int statusCode = 500}) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: RequestOptions(),
              response: Response<dynamic>(
                requestOptions: RequestOptions(),
                statusCode: statusCode,
              ),
              type: DioExceptionType.badResponse,
            ),
            true,
          );
        },
      ),
    );
  }

  group('NftRepository — getPortfolio', () {
    test('parses flat list payload into WeatherNftModel list', () async {
      stubResponse([
        {
          'id': 'nft-1',
          'type': 'streak',
          'tier': 'gold',
          'rarity': 'rare',
          'status': 'owned',
          'name': '7-Day Streak',
          'description': 'Collected 7 days in a row.',
          'earnedAt': '2026-04-01T12:00:00Z',
        },
        {
          'id': 'nft-2',
          'type': 'storm_chaser',
          'tier': 'platinum',
          'rarity': 'legendary',
          'status': 'claimable',
          'name': 'Storm Chaser Elite',
          'description': 'Tracked a Category-3 storm.',
        },
      ]);

      final result = await repository.getPortfolio('user-1');

      result.fold(
        (f) => fail('Expected nfts, got $f'),
        (nfts) {
          expect(nfts, hasLength(2));

          final streak = nfts[0];
          expect(streak.id, 'nft-1');
          expect(streak.type, NftType.streak);
          expect(streak.tier, 'gold');
          expect(streak.rarity, NftRarity.rare);
          expect(streak.status, NftStatus.owned);
          expect(streak.name, '7-Day Streak');
          expect(streak.earnedAt, '2026-04-01T12:00:00Z');
          expect(streak.isOwned, isTrue);

          final storm = nfts[1];
          expect(storm.id, 'nft-2');
          expect(storm.type, NftType.stormChaser);
          expect(storm.rarity, NftRarity.legendary);
          expect(storm.status, NftStatus.claimable);
          expect(storm.isClaimable, isTrue);
          expect(storm.earnedAt, isNull);
        },
      );
    });

    test('parses wrapped envelope payload', () async {
      stubResponse({
        'nfts': [
          {
            'id': 'nft-env',
            'type': 'streak',
            'tier': 'bronze',
            'rarity': 'common',
            'status': 'locked',
            'name': 'First Steps',
            'description': 'Collect your first reading.',
          },
        ],
      });

      final result = await repository.getPortfolio('user-2');

      result.fold(
        (f) => fail('Expected nfts, got $f'),
        (nfts) {
          expect(nfts, hasLength(1));
          expect(nfts.single.id, 'nft-env');
          expect(nfts.single.status, NftStatus.locked);
          expect(nfts.single.rarity, NftRarity.common);
        },
      );
    });

    test('returns empty list on 404 (backend not yet deployed)', () async {
      stubError(statusCode: 404);

      final result = await repository.getPortfolio('user-new');

      result.fold(
        (f) => fail('Expected empty list, got failure $f'),
        (nfts) => expect(nfts, isEmpty),
      );
    });

    test('returns failure on 500 error', () async {
      stubError(statusCode: 500);

      final result = await repository.getPortfolio('user-x');

      expect(result.isLeft(), isTrue);
    });

    test('returns empty list for empty response body', () async {
      stubResponse([]);

      final result = await repository.getPortfolio('user-3');

      result.fold(
        (f) => fail('Expected empty list, got $f'),
        (nfts) => expect(nfts, isEmpty),
      );
    });
  });

  group('NftRepository — claimNft', () {
    test('parses claim response into updated WeatherNftModel', () async {
      stubResponse({
        'nft': {
          'id': 'nft-1',
          'type': 'streak',
          'tier': 'gold',
          'rarity': 'rare',
          'status': 'owned',
          'name': '7-Day Streak',
          'description': 'Claimed.',
          'earnedAt': '2026-04-19T00:00:00Z',
        },
      });

      final result = await repository.claimNft('user-1', 'nft-1');

      result.fold(
        (f) => fail('Expected nft, got $f'),
        (nft) {
          expect(nft.id, 'nft-1');
          expect(nft.status, NftStatus.owned);
          expect(nft.earnedAt, '2026-04-19T00:00:00Z');
        },
      );
    });

    test('returns failure when claim endpoint errors', () async {
      stubError(statusCode: 422);

      final result = await repository.claimNft('user-1', 'nft-1');

      expect(result.isLeft(), isTrue);
    });
  });

  group('WeatherNftModel.fromJson', () {
    test('defaults to streak type for unknown type string', () {
      final nft = WeatherNftModel.fromJson(
        {'id': 'x', 'type': 'unknown_type', 'status': 'owned'},
      );
      expect(nft.type, NftType.streak);
    });

    test('defaults to common rarity for unknown rarity string', () {
      final nft = WeatherNftModel.fromJson(
        {'id': 'x', 'rarity': 'super_ultra', 'status': 'owned'},
      );
      expect(nft.rarity, NftRarity.common);
    });

    test('parses storm_chaser type alias', () {
      final nft = WeatherNftModel.fromJson(
        {'id': 'x', 'type': 'stormChaser', 'status': 'owned'},
      );
      expect(nft.type, NftType.stormChaser);
    });

    test('maps earnDate fallback field', () {
      final nft = WeatherNftModel.fromJson(
        {'id': 'x', 'status': 'owned', 'earnDate': '2026-04-01'},
      );
      expect(nft.earnedAt, '2026-04-01');
    });
  });
}
