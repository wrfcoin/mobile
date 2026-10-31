// Fakes-only tests of the live send check's STOP paths and bounds
// (test/test_helpers/live_send_check.dart). No network, no clock, safe in CI.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../test_helpers/live_send_check.dart';

Map<String, dynamic> _account(Object spendable) => {
  'ok': true,
  'data': {'spendable_balance': '$spendable', 'nonce': '0'},
};

class _Fake {
  _Fake({
    this.faucet = (200, const {}),
    this.ownNonce,
    this.sendError,
    this.nonceAfterSend,
    this.signInOk = true,
    this.ownAccount,
  });
  (int?, Object?)? ownAccount; // defaults to a rich sender
  (int?, Object?) faucet;
  BigInt? ownNonce;
  Object? sendError;
  BigInt? nonceAfterSend; // when set, the nonce read after the send returns it
  final calls = <String>[];
  final said = <String>[];
  bool signInOk;
  var signIns = 0;
  var sends = 0;
  var nonceReads = 0;
  var waits = 0;

  LiveSendPorts get ports => LiveSendPorts(
    readFaucet: () async {
      calls.add('faucet');
      return faucet;
    },
    signIn: () async {
      signIns += 1;
      calls.add('signin');
      return signInOk;
    },
    readOwnNonce: () async {
      nonceReads += 1;
      calls.add('nonce');
      return sends > 0 ? (nonceAfterSend ?? ownNonce) : ownNonce;
    },
    readOwnAccount: () async {
      calls.add('balance');
      return ownAccount ?? (200, _account(BigInt.from(10).pow(12)));
    },
    send: (nonce) async {
      sends += 1;
      calls.add('send');
      if (sendError != null) throw sendError!;
      return 'tx-abc';
    },
    wait: () async {
      waits += 1;
    },
    say: said.add,
  );
}

void main() {
  group('faucetStopReason', () {
    test('404 (account absent) stops with the plain message', () {
      expect(faucetStopReason(404, null), startsWith(faucetNotFundedMessage));
      expect(faucetNotFundedMessage, 'faucet not funded yet: run after E0f/H_F');
    });
    test('spendable_balance 0 stops', () {
      expect(faucetStopReason(200, _account(0)), contains('spendable_balance is 0'));
    });
    test('unreadable balance, other status and no answer stop', () {
      expect(faucetStopReason(200, {'data': {}}), contains('cannot read the faucet spendable_balance'));
      expect(faucetStopReason(200, {'data': {'spendable_balance': 'abc'}}), isNotNull);
      expect(faucetStopReason(500, null), contains('HTTP 500'));
      expect(faucetStopReason(401, null), contains('HTTP 401'));
      expect(faucetStopReason(null, null), contains('no answer'));
    });
    test('a missing, null, non-numeric or zero spendable_balance stops EVEN with a positive total balance', () {
      for (final data in <Map<String, Object?>>[
        {'balance': '99999999'},
        {'balance': '99999999', 'spendable_balance': null},
        {'balance': '99999999', 'spendable_balance': 'abc'},
        {'balance': '99999999', 'spendable_balance': '0'},
        {'balance': '99999999', 'spendable_balance': 0},
        {'balance': '99999999', 'spendable_balance': '-5'},
        {'balance': '99999999', 'spendable_balance': ''},
      ]) {
        expect(faucetStopReason(200, {'ok': true, 'data': data}), isNotNull, reason: '$data');
      }
      expect(faucetStopReason(200, {'ok': true}), isNotNull);
      expect(faucetStopReason(200, 'not a map'), isNotNull);
    });
    test('a positive spendable balance passes', () {
      expect(faucetStopReason(200, _account(33333333)), isNull);
    });
  });

  group('STOP happens before any claim or send', () {
    for (final (name, faucet) in <(String, (int?, Object?))>[
      ('absent (404)', (404, null)),
      ('zero balance', (200, _account(0))),
      ('node unreachable', (null, null)),
    ]) {
      test('faucet $name: check() and send() stop, nothing else is called', () async {
        final f = _Fake(faucet: faucet, ownNonce: BigInt.from(3));
        await expectLater(LiveSendCheck(f.ports).check(), throwsA(isA<LiveSendStop>()));
        await expectLater(LiveSendCheck(f.ports).send(), throwsA(isA<LiveSendStop>()));
        expect(f.calls, ['faucet', 'faucet']); // never read the wallet, never sent
        expect(f.sends, 0);
      });
    }

    test('a funded faucet but an unfunded wallet stops send() before signing', () async {
      final f = _Fake(faucet: (200, _account(5)));
      await expectLater(
        LiveSendCheck(f.ports).send(),
        throwsA(isA<LiveSendStop>().having((e) => e.message, 'message', contains('wallet not funded on chain yet'))),
      );
      expect(f.sends, 0);
    });

    test('check() reports FUNDED=yes/no and makes no transaction', () async {
      final unfunded = _Fake(faucet: (200, _account(5)));
      expect(await LiveSendCheck(unfunded.ports).check(), isFalse);
      expect(unfunded.said, contains('FUNDED=no'));
      final funded = _Fake(faucet: (200, _account(5)), ownNonce: BigInt.one);
      expect(await LiveSendCheck(funded.ports).check(), isTrue);
      expect(funded.said, contains('FUNDED=yes'));
      expect(funded.sends + unfunded.sends, 0);
    });
  });

  group('one send, bounded poll', () {
    test('success: exactly one send, settles when the nonce advances', () async {
      final f = _Fake(faucet: (200, _account(5)), ownNonce: BigInt.from(7), nonceAfterSend: BigInt.from(8));
      final result = await LiveSendCheck(f.ports).send();
      expect(result.settled, isTrue);
      expect(f.sends, 1);
      expect(f.said.join('\n'), contains('SETTLED nonce 7 -> 8'));
    });

    test('a failed send is not retried and the error propagates', () async {
      final f = _Fake(faucet: (200, _account(5)), ownNonce: BigInt.from(7), sendError: StateError('boom'));
      await expectLater(LiveSendCheck(f.ports).send(), throwsA(isA<StateError>()));
      expect(f.sends, 1);
    });

    test('the inclusion poll never reads more than $maxInclusionPolls times and reports NOT SETTLED', () async {
      final f = _Fake(faucet: (200, _account(5)), ownNonce: BigInt.from(7)); // nonce never advances
      final result = await LiveSendCheck(f.ports).send();
      expect(result.settled, isFalse);
      expect(result.polls, maxInclusionPolls);
      expect(f.waits, maxInclusionPolls);
      expect(f.nonceReads, 1 + maxInclusionPolls); // 1 before the send + the bounded poll
      expect(f.sends, 1);
      expect(f.said.join('\n'), contains('NOT SETTLED'));
    });

    test('a larger requested poll is clamped to the maximum', () async {
      var reads = 0;
      final result = await pollNonceAdvance(
        readNonce: () async {
          reads += 1;
          return BigInt.one;
        },
        before: BigInt.one,
        wait: () async {},
        maxPolls: 500,
      );
      expect(result.polls, maxInclusionPolls);
      expect(reads, maxInclusionPolls);
    });
  });

  group('explicit sign-in (the client never logs in on its own)', () {
    test('check and send sign in AFTER the faucet precondition and BEFORE the first wallet read', () async {
      final f = _Fake(faucet: (200, _account(5)), ownNonce: BigInt.from(7), nonceAfterSend: BigInt.from(8));
      await LiveSendCheck(f.ports).send();
      expect(f.calls.take(3).toList(), ['faucet', 'signin', 'nonce']);
      final c = _Fake(faucet: (200, _account(5)), ownNonce: BigInt.from(7));
      await LiveSendCheck(c.ports).check();
      expect(c.calls, ['faucet', 'signin', 'nonce']);
    });
    test('a failed sign-in STOPs before any wallet read or send', () async {
      final f = _Fake(faucet: (200, _account(5)), ownNonce: BigInt.from(7), signInOk: false);
      await expectLater(LiveSendCheck(f.ports).send(), throwsA(isA<LiveSendStop>()));
      await expectLater(LiveSendCheck(f.ports).check(), throwsA(isA<LiveSendStop>()));
      expect(f.nonceReads, 0);
      expect(f.sends, 0);
    });
    test('an unfunded or unreadable faucet never reaches sign-in', () async {
      for (final faucet in <(int?, Object?)>[(404, null), (200, _account(0)), (null, null), (200, {'data': {'balance': '9'}})]) {
        final f = _Fake(faucet: faucet, ownNonce: BigInt.one);
        await expectLater(LiveSendCheck(f.ports).check(), throwsA(isA<LiveSendStop>()));
        await expectLater(LiveSendCheck(f.ports).send(), throwsA(isA<LiveSendStop>()));
        expect(f.signIns, 0);
      }
    });
  });

  group('unknown send outcome', () {
    test('LiveSendUnknownOutcome STOPs with the check-the-nonce message, one send, no poll', () async {
      final f = _Fake(faucet: (200, _account(5)), ownNonce: BigInt.from(7), sendError: const LiveSendUnknownOutcome());
      await expectLater(
        LiveSendCheck(f.ports).send(),
        throwsA(isA<LiveSendStop>().having((e) => '$e', 'message', contains('check the wallet nonce'))),
      );
      expect(f.sends, 1);
      expect(f.waits, 0);
      expect(f.nonceReads, 1);
      expect(f.said.join('\n'), contains('unknown outcome'));
      expect(unknownOutcomeMessage, contains('check the wallet nonce'));
      expect(unknownOutcomeMessage, contains('before retrying'));
    });
  });

  group('one-shot transport: exactly one POST on the wire', () {
    const seed = '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
    Future<(WalletRemoteDataSource, _CountingAdapter, Ed25519TransferSigner, String)> build(
      _CountingAdapter adapter,
    ) async {
      final signer = await Ed25519TransferSigner.fromSeedHex(seed);
      final from = WalletSetupService().chainAddressFromEd25519(signer.publicKey);
      final dio = oneShotDio(baseUrl: 'http://127.0.0.1:1', bearer: 'jwt-test-value', adapter: adapter);
      return (
        WalletRemoteDataSource(dio, signingDomain: const TransferSigningDomain(chainId: liveChainId, networkId: liveNetworkId)),
        adapter,
        signer,
        from,
      );
    }

    final to = '0x${'b2' * 20}';

    test('a receive timeout is ONE POST and becomes an unknown outcome', () async {
      final (wallets, adapter, signer, from) = await build(_CountingAdapter(postBehaviour: _Post.timeout));
      await expectLater(
        sendOnce(wallets: wallets, from: from, to: to, amountBaseUnits: '100000000', signer: signer),
        throwsA(isA<LiveSendUnknownOutcome>()),
      );
      expect(adapter.posts, 1);
      expect(adapter.gets, 1); // the nonce read inside sendTransaction
    });

    test('a 503 is ONE POST and an unknown outcome', () async {
      final (wallets, adapter, signer, from) = await build(_CountingAdapter(postBehaviour: _Post.status503));
      await expectLater(
        sendOnce(wallets: wallets, from: from, to: to, amountBaseUnits: '100000000', signer: signer),
        throwsA(isA<LiveSendUnknownOutcome>()),
      );
      expect(adapter.posts, 1);
    });

    test('a definite 400 is ONE POST and propagates as the DioException', () async {
      final (wallets, adapter, signer, from) = await build(_CountingAdapter(postBehaviour: _Post.status400));
      await expectLater(
        sendOnce(wallets: wallets, from: from, to: to, amountBaseUnits: '100000000', signer: signer),
        throwsA(isA<DioException>()),
      );
      expect(adapter.posts, 1);
    });

    test('success is ONE POST and returns the hash', () async {
      final (wallets, adapter, signer, from) = await build(_CountingAdapter(postBehaviour: _Post.ok));
      expect(
        await sendOnce(wallets: wallets, from: from, to: to, amountBaseUnits: '100000000', signer: signer),
        'tx-hash-1',
      );
      expect(adapter.posts, 1);
    });

    test('the inclusion poll over the one-shot transport never exceeds the wire bound on timeouts', () async {
      final adapter = _CountingAdapter(postBehaviour: _Post.ok, getBehaviour: _Post.timeout);
      final dio = oneShotDio(baseUrl: 'http://127.0.0.1:1', bearer: 'jwt-test-value', adapter: adapter);
      final wallets = WalletRemoteDataSource(dio);
      await expectLater(
        pollNonceAdvance(
          readNonce: () async => BigInt.parse(await wallets.getAccountNonce('0x${'a1' * 20}')),
          before: BigInt.one,
          wait: () async {},
        ),
        throwsA(isA<DioException>()),
      );
      expect(adapter.gets, 1); // a failed read is not retried by the transport
    });

    test('oneShotDio carries no interceptors (so no retry) and the bearer', () {
      final dio = oneShotDio(baseUrl: 'http://127.0.0.1:1', bearer: 'jwt-test-value');
      expect(dio.interceptors.whereType<InterceptorsWrapper>(), isEmpty);
      expect(dio.interceptors.length, lessThanOrEqualTo(1)); // Dio's own ImplyContentType only
      expect(dio.options.headers['Authorization'], 'Bearer jwt-test-value');
    });
  });

  group('public output only', () {
    test('publicLine refuses a line containing a secret and passes public data', () {
      const secrets = ['abandon ability able about above absent', 'reader-token-123456', 'eyJhbGciOi.jwt.payload'];
      expect(publicLine('ADDRESS=0x${'a' * 40} nonce=3 tx=abc', secrets), contains('nonce=3'));
      for (final secret in secrets) {
        expect(() => publicLine('oops $secret', secrets), throwsStateError);
      }
    });

    test('short or empty secrets do not block ordinary lines', () {
      expect(publicLine('nonce=3', ['', 'ab']), 'nonce=3');
    });

    test('the signing domain is explicitly 888 / testnet', () {
      expect(liveChainId, '888');
      expect(liveNetworkId, 'testnet');
    });
  });

  group('sender balance guard (amount + fee reserve)', () {
    const amount = '100000000'; // 1 WRF
    const fee = '1000000'; // 0.01 WRF
    final need = BigInt.parse(amount) + BigInt.parse(fee);

    test('senderStopReason: enough passes, exactly amount+fee passes', () {
      expect(senderStopReason(200, _account(need), amountBaseUnits: amount, feeReserveBaseUnits: fee), isNull);
      expect(senderStopReason(200, _account(need + BigInt.one), amountBaseUnits: amount, feeReserveBaseUnits: fee), isNull);
    });
    test('senderStopReason: one base unit short stops and names the figures', () {
      final r = senderStopReason(200, _account(need - BigInt.one), amountBaseUnits: amount, feeReserveBaseUnits: fee);
      expect(r, contains('below amount + fee'));
      expect(r, contains('$need'));
    });
    test('senderStopReason: unreadable, 404, non-numeric and total-only balances stop', () {
      for (final (s, b) in <(int?, Object?)>[
        (null, null),
        (404, null),
        (500, null),
        (200, {'ok': true, 'data': {'spendable_balance': 'x'}}),
        (200, {'ok': true, 'data': {'balance': '999999999999'}}),
      ]) {
        expect(senderStopReason(s, b, amountBaseUnits: amount, feeReserveBaseUnits: fee), isNotNull, reason: '$s $b');
      }
    });
    test('send() with a low balance STOPs before signing or sending', () async {
      final f = _Fake(
        faucet: (200, _account(5)),
        ownNonce: BigInt.one,
        ownAccount: (200, _account(need - BigInt.one)),
      );
      await expectLater(
        LiveSendCheck(f.ports, amountBaseUnits: amount, feeReserveBaseUnits: fee).send(),
        throwsA(isA<LiveSendStop>().having((e) => e.message, 'message', contains('below amount + fee'))),
      );
      expect(f.sends, 0);
      expect(f.calls, contains('balance'));
    });
    test('send() with exactly enough balance sends once', () async {
      final f = _Fake(
        faucet: (200, _account(5)),
        ownNonce: BigInt.one,
        nonceAfterSend: BigInt.two,
        ownAccount: (200, _account(need)),
      );
      await LiveSendCheck(f.ports, amountBaseUnits: amount, feeReserveBaseUnits: fee).send();
      expect(f.sends, 1);
    });
  });

  group('explicit recipient', () {
    const good = '0x1111111111111111111111111111111111111111';
    test('a valid recipient is lowercased and used', () {
      expect(
        resolveRecipient(recipient: good.toUpperCase().replaceFirst('0X', '0x'), selfTest: false, random: () => 'x'),
        good,
      );
    });
    test('missing recipient without self-test mode is refused', () {
      for (final r in ['', '  ']) {
        expect(
          () => resolveRecipient(recipient: r, selfTest: false, random: () => good),
          throwsA(isA<LiveSendStop>().having((e) => e.message, 'm', contains('WRFCOIN_LIVE_RECIPIENT'))),
        );
      }
    });
    test('a malformed recipient is refused, even in self-test mode', () {
      for (final selfTest in [false, true]) {
        expect(
          () => resolveRecipient(recipient: '0x123', selfTest: selfTest, random: () => good),
          throwsA(isA<LiveSendStop>()),
        );
      }
    });
    test('self-test mode with no recipient uses the random throwaway', () {
      expect(resolveRecipient(recipient: '', selfTest: true, random: () => good), good);
    });
    test('the sender is never accepted as its own recipient', () {
      expect(
        () => resolveRecipient(recipient: good, selfTest: false, random: () => good, sender: good),
        throwsA(isA<LiveSendStop>()),
      );
    });
  });
}

enum _Post { ok, timeout, status503, status400 }

class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter({this.postBehaviour = _Post.ok, this.getBehaviour = _Post.ok});
  final _Post postBehaviour;
  final _Post getBehaviour;
  var posts = 0;
  var gets = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final isPost = options.method.toUpperCase() == 'POST';
    if (isPost) {
      posts += 1;
    } else {
      gets += 1;
    }
    final behaviour = isPost ? postBehaviour : getBehaviour;
    switch (behaviour) {
      case _Post.timeout:
        throw DioException(requestOptions: options, type: DioExceptionType.receiveTimeout);
      case _Post.status503:
        return _json(options, 503, {'error': 'unavailable'});
      case _Post.status400:
        return _json(options, 400, {'error': 'AUTHORIZATION_INVALID'});
      case _Post.ok:
        return isPost
            ? _json(options, 200, {'hash': 'tx-hash-1', 'status': 'submitted'})
            : _json(options, 200, {'nonce': '7', 'data': {'nonce': '7'}});
    }
  }

  ResponseBody _json(RequestOptions o, int code, Map<String, Object?> body) => ResponseBody.fromString(
    jsonEncode(body),
    code,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}
