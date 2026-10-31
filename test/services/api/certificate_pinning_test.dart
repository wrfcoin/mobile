import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/api/certificate_pin_validator.dart';
import 'package:wrfcoin_mobile/services/api/dio_adapter_native.dart';
import 'package:wrfcoin_mobile/services/api/pinnable_ca_certificates.dart';

/// SPKI pins of the bundled CAs, computed independently with
/// `openssl x509 -pubkey -noout | openssl pkey -pubin -outform der |
/// openssl dgst -sha256` (docs/RELEASING.md).
const _bundledPins = {
  'GTS WE1': '908769E8D34477CC2CBA0632C88605B22D7294C0840F78596D247C645B1AFC0E',
  'GTS WR1': 'C83BBDA20DB9E4D3791847FE0706BDAD3AEA150D04C9D674AF514287D4DD016E',
  'GTS Root R4':
      '9847E5653E5E9E847516E5CB818606AA7544A19BE67FD7366D506988E8D84347',
  'GTS Root R1':
      '871A9194F4EED5B312FF40C84C1D524AED2F778BBFF25F138CF81F680A7ADC67',
};

Uint8List _der(PinnableCaCertificate certificate) =>
    base64.decode(certificate.derBase64);

String _colonHex(String hex) =>
    [for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2)].join(':');

void main() {
  group('SPKI pins', () {
    test('every bundled CA hashes to its documented SPKI pin', () {
      expect({
        for (final certificate in pinnableCaCertificates)
          certificate.name: spkiSha256Pin(_der(certificate)),
      }, _bundledPins);
    });

    test('pin comparison ignores case and colons', () {
      final we1 = _der(gtsWe1);
      final pin = _bundledPins['GTS WE1']!;
      expect(certificateMatchesSpkiPins(we1, [pin]), isTrue);
      expect(certificateMatchesSpkiPins(we1, [pin.toLowerCase()]), isTrue);
      expect(certificateMatchesSpkiPins(we1, [_colonHex(pin)]), isTrue);
      expect(
        certificateMatchesSpkiPins(we1, [_bundledPins['GTS Root R4']!]),
        isFalse,
      );
    });

    test('a missing, empty or malformed certificate never matches', () {
      final pin = _bundledPins['GTS WE1']!;
      expect(certificateMatchesSpkiPins(null, [pin]), isFalse);
      expect(certificateMatchesSpkiPins(Uint8List(0), [pin]), isFalse);
      expect(
        certificateMatchesSpkiPins(Uint8List.fromList([0x30, 0x05, 1]), [pin]),
        isFalse,
      );
      expect(certificateMatchesSpkiPins(_der(gtsWe1), const []), isFalse);
    });

    test('the leaf-certificate DER hash is not an SPKI pin', () {
      // The old scheme pinned sha256(certificate DER); that value must not
      // be accepted as the key pin.
      final we1 = _der(gtsWe1);
      expect(spkiSha256Pin(we1), isNot(_bundledPins['GTS Root R4']));
      expect(subjectPublicKeyInfoDer(we1).length, lessThan(we1.length));
    });
  });

  group('pinned trust anchors', () {
    test('select exactly the bundled CAs for the configured pins', () {
      final anchors = pinnedTrustAnchors([
        _bundledPins['GTS WE1']!,
        _bundledPins['GTS Root R4']!,
      ]);
      expect(anchors.map(spkiSha256Pin), [
        _bundledPins['GTS WE1'],
        _bundledPins['GTS Root R4'],
      ]);
    });

    test('fail closed on a pin with no bundled CA, or no pin at all', () {
      expect(
        () => pinnedTrustAnchors([_bundledPins['GTS WE1']!, '00' * 32]),
        throwsStateError,
      );
      expect(() => pinnedTrustAnchors(const []), throwsStateError);
    });
  });

  group('TLS handshake against a local chain', () {
    late Directory dir;
    late HttpServer server;
    late _TestPki pki;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('spki-pin-test');
      pki = await _TestPki.create(dir);
      final serverContext = SecurityContext()
        ..useCertificateChainBytes(
          utf8.encode(pki.leafPem + pki.intermediatePem),
        )
        ..usePrivateKeyBytes(utf8.encode(pki.leafKeyPem));
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      server.listen((request) {
        request.response
          ..statusCode = 200
          ..write('ok')
          ..close();
      }, onError: (_) {});
    });

    tearDownAll(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    Future<int> get(String pin) async {
      final catalog = [
        PinnableCaCertificate('root', pki.rootDer),
        PinnableCaCertificate('intermediate', pki.intermediateDer),
        PinnableCaCertificate('unrelated', pki.unrelatedDer),
      ];
      final client = pinnedHttpClient(
        pinnedSecurityContext([pin], catalog: catalog),
      );
      try {
        final request = await client.getUrl(
          Uri.parse('https://localhost:${server.port}/'),
        );
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    String pinOf(String derBase64) => spkiSha256Pin(base64.decode(derBase64));

    test('a pin on the intermediate accepts the chain', () async {
      expect(await get(pinOf(pki.intermediateDer)), 200);
    });

    test('a pin on the root accepts the chain', () async {
      expect(await get(pinOf(pki.rootDer)), 200);
    });

    test('a pin on an unrelated CA refuses the handshake', () async {
      await expectLater(
        get(pinOf(pki.unrelatedDer)),
        throwsA(isA<HandshakeException>()),
      );
    });
  });
}

/// A throwaway root -> intermediate -> leaf (localhost) chain plus an
/// unrelated CA, generated per run with the openssl CLI so no private key is
/// committed.
class _TestPki {
  _TestPki({
    required this.rootDer,
    required this.intermediateDer,
    required this.unrelatedDer,
    required this.intermediatePem,
    required this.leafPem,
    required this.leafKeyPem,
  });

  final String rootDer;
  final String intermediateDer;
  final String unrelatedDer;
  final String intermediatePem;
  final String leafPem;
  final String leafKeyPem;

  static Future<_TestPki> create(Directory dir) async {
    Future<void> openssl(List<String> args) async {
      final result = await Process.run(
        'openssl',
        args,
        workingDirectory: dir.path,
      );
      if (result.exitCode != 0) {
        throw StateError('openssl ${args.first} failed: ${result.stderr}');
      }
    }

    File file(String name) => File('${dir.path}/$name');
    Future<void> ext(String name, String body) =>
        file(name).writeAsString(body);
    const ecKey = ['-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256'];
    const caExt =
        'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n';

    for (final name in ['root', 'unrelated']) {
      await openssl([
        'req', '-x509', ...ecKey, '-nodes', '-keyout', '$name.key', //
        '-out', '$name.pem', '-days', '2', '-subj', '/CN=Pin test $name',
        '-addext', 'basicConstraints=critical,CA:TRUE',
        '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
      ]);
    }
    await ext('int.ext', caExt);
    await openssl([
      'req', '-new', ...ecKey, '-nodes', '-keyout', 'int.key', //
      '-out', 'int.csr', '-subj', '/CN=Pin test intermediate',
    ]);
    await openssl([
      'x509', '-req', '-in', 'int.csr', '-CA', 'root.pem', //
      '-CAkey', 'root.key', '-set_serial', '2', '-days', '2',
      '-extfile', 'int.ext', '-out', 'int.pem',
    ]);
    await ext(
      'leaf.ext',
      'basicConstraints=CA:FALSE\nsubjectAltName=DNS:localhost\n'
          'extendedKeyUsage=serverAuth\n',
    );
    await openssl([
      'req', '-new', ...ecKey, '-nodes', '-keyout', 'leaf.key', //
      '-out', 'leaf.csr', '-subj', '/CN=localhost',
    ]);
    await openssl([
      'x509', '-req', '-in', 'leaf.csr', '-CA', 'int.pem', //
      '-CAkey', 'int.key', '-set_serial', '3', '-days', '2',
      '-extfile', 'leaf.ext', '-out', 'leaf.pem',
    ]);

    Future<String> derBase64(String pem) async {
      final text = await file(pem).readAsString();
      return text
          .split('\n')
          .where((line) => line.isNotEmpty && !line.startsWith('-----'))
          .join();
    }

    return _TestPki(
      rootDer: await derBase64('root.pem'),
      intermediateDer: await derBase64('int.pem'),
      unrelatedDer: await derBase64('unrelated.pem'),
      intermediatePem: await file('int.pem').readAsString(),
      leafPem: await file('leaf.pem').readAsString(),
      leafKeyPem: await file('leaf.key').readAsString(),
    );
  }
}
