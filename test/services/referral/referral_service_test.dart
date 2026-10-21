import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/referral/referral_service.dart';

void main() {
  group('ReferralService', () {
    late List<Map<String, dynamic>> requests;
    late Dio dio;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      requests = <Map<String, dynamic>>[];
      dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(<String, dynamic>{
              'path': options.path,
              'data': options.data,
            });

            if (options.path == ApiConstants.referralGenerate) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: const <String, dynamic>{
                    'success': true,
                    'data': {'referralCode': 'ABC12345'},
                  },
                ),
              );
              return;
            }

            if (options.path == ApiConstants.referralActivate) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data:
                      jsonDecode(
                            '{"success":true,"data":{"referralCode":"ABC12345","rewardAmountWrf":100}}',
                          )
                          as Map<String, dynamic>,
                ),
              );
              return;
            }

            handler.next(options);
          },
        ),
      );
    });

    test('generates invite links from backend-issued referral codes', () async {
      final service = ReferralService(
        apiClient: ApiClient(dio: dio),
        prefs: await SharedPreferences.getInstance(),
      );

      final referralCode = await service.generateReferralCode('wrf1abc');

      expect(referralCode, 'ABC12345');
      expect(
        service.createInviteDeepLink(referralCode),
        'wrfcoin://invite?ref=ABC12345',
      );
      expect(requests.single['path'], ApiConstants.referralGenerate);
      expect(requests.single['data'], {'walletAddress': 'wrf1abc'});
    });

    test('captures invite links and activates attribution on signup', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ReferralService(
        apiClient: ApiClient(dio: dio),
        prefs: prefs,
      );

      expect(
        await service.captureInviteLink('wrfcoin://invite?ref=ABC12345'),
        isTrue,
      );
      expect(await service.getPendingReferralCode(), 'ABC12345');

      final activated = await service.trackReferralAttributionOnSignup(
        refereeAddress: 'wrf1newwallet',
      );

      expect(activated, isTrue);
      expect(await service.getPendingReferralCode(), isNull);
      expect(requests.last['path'], ApiConstants.referralActivate);
      expect(requests.last['data'], {
        'referralCode': 'ABC12345',
        'refereeAddress': 'wrf1newwallet',
      });
    });

    test('rejects non-invite deep links', () async {
      final service = ReferralService(
        apiClient: ApiClient(dio: dio),
        prefs: await SharedPreferences.getInstance(),
      );

      expect(
        service.extractReferralCode(
          Uri.parse('wrfcoin://profile?ref=ABC12345'),
        ),
        isNull,
      );
    });

    test('accepts route-style invite paths for startup capture', () async {
      final service = ReferralService(
        apiClient: ApiClient(dio: dio),
        prefs: await SharedPreferences.getInstance(),
      );

      expect(
        service.extractReferralCode(Uri.parse('/invite?ref=ABC12345')),
        'ABC12345',
      );
    });
  });
}
