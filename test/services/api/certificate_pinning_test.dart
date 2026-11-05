import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/api/certificate_pin_validator.dart';
import 'package:wrfcoin_mobile/services/api/dio_adapter_native.dart';
import 'package:wrfcoin_mobile/services/api/pinnable_ca_certificates.dart';
import 'package:wrfcoin_mobile/services/api/tls_pin_configuration.dart';

/// SPKI pins of the bundled roots, computed independently with
/// `openssl x509 -pubkey -noout | openssl pkey -pubin -outform der |
/// openssl dgst -sha256` from each CA's own download (docs/RELEASING.md).
const _bundledPins = {
  'GTS Root R1':
      '871A9194F4EED5B312FF40C84C1D524AED2F778BBFF25F138CF81F680A7ADC67',
  'GTS Root R4':
      '9847E5653E5E9E847516E5CB818606AA7544A19BE67FD7366D506988E8D84347',
  'ISRG Root X1':
      '0B9FA5A59EED715C26C1020C711B4F6EC42D58B0015E14337A39DAD301C5AFC3',
  'ISRG Root X2':
      '762195C225586EE6C0237456E2107DC54F1EFC21F61A792EBD515913CCE68332',
  'USERTrust ECC Certification Authority':
      '2021917E98263945C859C43F1D73CB4139053C414FA03CA3BC7EE88614298F3B',
  'USERTrust RSA Certification Authority':
      'C784333D20BCD742B9FDC3236F4E509B8937070E73067E254DD3BF9C45BF4DDE',
  'Sectigo Public Server Authentication Root E46':
      'B0B56335468561F5BB9FA12D801784A633A572705D34F32B643445DFA8B005D1',
  'Sectigo Public Server Authentication Root R46':
      '0E8BB18BBEEFB381BE21BFC1A206D317298462AD104855F04A0542699708D3D4',
  'SSL.com TLS ECC Root CA 2022':
      '1BF00D5C8F13C094DD17E00504CF0888850F12FD067FA1F92C0FDBF60B86E321',
  'SSL.com TLS RSA Root CA 2022':
      '2BCF553A66F570900DDD32BA6DFE1ECC06C9182D662DC1B60E1F7B767C2BDD54',
};

const _cloudflareAuthorities = {
  'Google Trust Services',
  "Let's Encrypt",
  'Sectigo',
  'SSL.com',
};

Uint8List _der(PinnableCaCertificate certificate) =>
    base64.decode(certificate.derBase64);

String _colonHex(String hex) =>
    [for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2)].join(':');

List<String> get _releasePins => TlsPinConfiguration(
  profile: tlsPublicReleaseProfile,
  pinSet: 'cloudflare-universal-v1',
  isProductBuild: true,
).validatedPins();

void main() {
  group('SPKI pins', () {
    test('every bundled root hashes to its documented SPKI pin', () {
      expect({
        for (final certificate in pinnableCaCertificates)
          certificate.name: spkiSha256Pin(_der(certificate)),
      }, _bundledPins);
    });

    test('pin comparison ignores case and colons', () {
      final r4 = _der(gtsRootR4);
      final pin = _bundledPins['GTS Root R4']!;
      expect(certificateMatchesSpkiPins(r4, [pin]), isTrue);
      expect(certificateMatchesSpkiPins(r4, [pin.toLowerCase()]), isTrue);
      expect(certificateMatchesSpkiPins(r4, [_colonHex(pin)]), isTrue);
      expect(
        certificateMatchesSpkiPins(r4, [_bundledPins['GTS Root R1']!]),
        isFalse,
      );
    });

    test('a missing, empty or malformed certificate never matches', () {
      final pin = _bundledPins['GTS Root R4']!;
      expect(certificateMatchesSpkiPins(null, [pin]), isFalse);
      expect(certificateMatchesSpkiPins(Uint8List(0), [pin]), isFalse);
      expect(
        certificateMatchesSpkiPins(Uint8List.fromList([0x30, 0x05, 1]), [pin]),
        isFalse,
      );
      expect(certificateMatchesSpkiPins(_der(gtsRootR4), const []), isFalse);
    });

    test('the certificate DER hash is not an SPKI pin', () {
      final r4 = _der(gtsRootR4);
      expect(subjectPublicKeyInfoDer(r4).length, lessThan(r4.length));
    });
  });

  group('release pin set', () {
    test('pins exactly the bundled roots', () {
      expect(
        _releasePins.map(normalizeCertificatePin).toSet(),
        _bundledPins.values.toSet(),
      );
    });

    test('covers all four CAs Cloudflare may use, with two roots each '
        '(four for Sectigo)', () {
      final byAuthority = <String, List<String>>{};
      for (final certificate in pinnableCaCertificates) {
        byAuthority
            .putIfAbsent(certificate.authority, () => [])
            .add(certificate.name);
      }
      expect(byAuthority.keys.toSet(), _cloudflareAuthorities);
      expect(byAuthority.map((k, v) => MapEntry(k, v.length)), {
        'Google Trust Services': 2,
        "Let's Encrypt": 2,
        'Sectigo': 4,
        'SSL.com': 2,
      });
    });

    test('every pin selects exactly one bundled root as a trust anchor', () {
      final anchors = pinnedTrustAnchors(_releasePins);
      expect(anchors, hasLength(10));
      expect(anchors.map(spkiSha256Pin).toSet(), _bundledPins.values.toSet());
    });

    test('fail closed on a pin with no bundled root, or no pin at all', () {
      expect(
        () => pinnedTrustAnchors([..._releasePins, '00' * 32]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('matches no bundled CA certificate'),
          ),
        ),
      );
      expect(() => pinnedTrustAnchors(const []), throwsStateError);
      expect(() => pinnedSecurityContext(['00' * 32]), throwsStateError);
    });
  });

  group('TLS handshake against synthetic chains from four CAs', () {
    late Directory dir;
    late _SyntheticPki pki;
    final servers = <String, HttpServer>{};

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('spki-pin-set-test');
      pki = await _SyntheticPki.create(dir);
      for (final hierarchy in pki.all) {
        final context = SecurityContext()
          ..useCertificateChainBytes(utf8.encode(hierarchy.servedChainPem))
          ..usePrivateKeyBytes(utf8.encode(hierarchy.leafKeyPem));
        final server = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          context,
        );
        server.listen((request) {
          request.response
            ..statusCode = 200
            ..write('ok')
            ..close();
        }, onError: (_) {});
        servers[hierarchy.name] = server;
      }
    });

    tearDownAll(() async {
      for (final server in servers.values) {
        await server.close(force: true);
      }
      await dir.delete(recursive: true);
    });

    /// The catalog and pin set the app would ship if these synthetic roots
    /// were the four Cloudflare CAs.
    List<PinnableCaCertificate> catalog() => [
      for (final hierarchy in pki.listed)
        PinnableCaCertificate(
          hierarchy.name,
          hierarchy.rootDer,
          authority: hierarchy.name,
        ),
    ];

    List<String> pinsOf(Iterable<_Hierarchy> hierarchies) => [
      for (final hierarchy in hierarchies)
        spkiSha256Pin(base64.decode(hierarchy.rootDer)),
    ];

    Future<int> get(String server, List<String> pins) async {
      final client = pinnedHttpClient(
        pinnedSecurityContext(pins, catalog: catalog()),
      );
      try {
        final request = await client.getUrl(
          Uri.parse('https://localhost:${servers[server]!.port}/'),
        );
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    for (final name in _SyntheticPki.listedNames) {
      test('the pin set accepts a $name chain', () async {
        expect(await get(name, pinsOf(pki.listed)), 200);
      });
    }

    test('the pin set refuses a chain from an unlisted CA', () async {
      await expectLater(
        get(_SyntheticPki.unlistedName, pinsOf(pki.listed)),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('a one-CA pin set refuses the other CAs (the old failure)', () async {
      final gtsOnly = pinsOf(pki.listed.where((h) => h.name == 'GTS-like'));
      expect(await get('GTS-like', gtsOnly), 200);
      for (final name in _SyntheticPki.listedNames.skip(1)) {
        await expectLater(
          get(name, gtsOnly),
          throwsA(isA<HandshakeException>()),
          reason: name,
        );
      }
    });
  });
}

/// One synthetic CA: a pinned root and the chain a server presents.
class _Hierarchy {
  _Hierarchy({
    required this.name,
    required this.rootDer,
    required this.servedChainPem,
    required this.leafKeyPem,
  });

  final String name;

  /// The self-signed root (base64 DER) that the app would bundle and pin.
  final String rootDer;

  /// leaf, intermediates and (where the real CA does so) the root
  /// cross-signed by an older root that is NOT pinned.
  final String servedChainPem;
  final String leafKeyPem;
}

/// Throwaway hierarchies shaped like the chains Cloudflare serves, generated
/// per run with the openssl CLI so no private key is committed:
///
/// - GTS-like (ECDSA): leaf, intermediate, root cross-signed by a legacy root
///   (GTS Root R4 is served cross-signed by GlobalSign).
/// - LE-like (RSA): leaf, intermediate.
/// - Sectigo-like (ECDSA): leaf, intermediate.
/// - SSL.com-like (RSA): leaf, issuing CA, transit CA, root cross-signed by a
///   legacy root (Cloudflare TLS Issuing CA, SSL.com TLS Transit CA R2,
///   SSL.com TLS Root CA 2022 x SecureTrust).
/// - Unlisted (ECDSA): leaf, intermediate, from a root the app does not pin.
class _SyntheticPki {
  _SyntheticPki(this.listed, this.unlisted);

  static const listedNames = [
    'GTS-like',
    'LE-like',
    'Sectigo-like',
    'SSL.com-like',
  ];
  static const unlistedName = 'Unlisted';

  final List<_Hierarchy> listed;
  final _Hierarchy unlisted;

  List<_Hierarchy> get all => [...listed, unlisted];

  static Future<_SyntheticPki> create(Directory dir) async {
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
    await file('ca.ext').writeAsString(
      'basicConstraints=critical,CA:TRUE\n'
      'keyUsage=critical,keyCertSign,cRLSign\n',
    );
    await file('leaf.ext').writeAsString(
      'basicConstraints=CA:FALSE\nsubjectAltName=DNS:localhost\n'
      'extendedKeyUsage=serverAuth\n',
    );
    var serial = 10;

    List<String> newKey(bool rsa) => rsa
        ? ['-newkey', 'rsa:2048']
        : ['-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256'];

    Future<void> selfSigned(String id, String cn, bool rsa) => openssl([
      'req', '-x509', ...newKey(rsa), '-nodes', '-keyout', '$id.key', //
      '-out', '$id.pem', '-days', '2', '-subj', '/CN=$cn',
      '-addext', 'basicConstraints=critical,CA:TRUE',
      '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
    ]);

    /// Signs a certificate for [id] (a new key, or [id].key when [reuseKey])
    /// with the CA [issuer].
    Future<void> issue(
      String id,
      String cn,
      String issuer, {
      required bool rsa,
      bool leaf = false,
      bool reuseKey = false,
      String? out,
    }) async {
      await openssl([
        'req', '-new', //
        if (reuseKey) ...[
          '-key',
          '$id.key',
        ] else ...[
          ...newKey(rsa),
          '-nodes',
          '-keyout',
          '$id.key',
        ],
        '-out', '$id.csr', '-subj', '/CN=$cn',
      ]);
      await openssl([
        'x509', '-req', '-in', '$id.csr', '-CA', '$issuer.pem', //
        '-CAkey', '$issuer.key', '-set_serial', '${serial++}', '-days', '2',
        '-extfile', leaf ? 'leaf.ext' : 'ca.ext', '-out', out ?? '$id.pem',
      ]);
    }

    Future<String> pem(String id) => file('$id.pem').readAsString();
    Future<String> derBase64(String id) async =>
        (await pem(id))
            .split('\n')
            .where((line) => line.isNotEmpty && !line.startsWith('-----'))
            .join();

    Future<_Hierarchy> hierarchy(
      String name, {
      required bool rsa,
      bool crossSigned = false,
      bool transit = false,
    }) async {
      final p = name.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
      await selfSigned('${p}root', '$name Root', rsa);
      final served = <String>[];
      if (crossSigned) {
        await selfSigned('${p}legacy', '$name Legacy Root', rsa);
        // Same subject and key as the pinned root, issued by the legacy root.
        await issue(
          '${p}root',
          '$name Root',
          '${p}legacy',
          rsa: rsa,
          reuseKey: true,
          out: '${p}cross.pem',
        );
        served.add('${p}cross');
      }
      var issuer = '${p}root';
      if (transit) {
        await issue('${p}transit', '$name Transit CA', issuer, rsa: rsa);
        served.insert(0, '${p}transit');
        issuer = '${p}transit';
      }
      await issue('${p}int', '$name Issuing CA', issuer, rsa: rsa);
      served.insert(0, '${p}int');
      await issue('${p}leaf', 'localhost', '${p}int', rsa: rsa, leaf: true);
      served.insert(0, '${p}leaf');
      return _Hierarchy(
        name: name,
        rootDer: await derBase64('${p}root'),
        servedChainPem: (await Future.wait(served.map(pem))).join(),
        leafKeyPem: await file('${p}leaf.key').readAsString(),
      );
    }

    return _SyntheticPki([
      await hierarchy('GTS-like', rsa: false, crossSigned: true),
      await hierarchy('LE-like', rsa: true),
      await hierarchy('Sectigo-like', rsa: false),
      await hierarchy(
        'SSL.com-like',
        rsa: true,
        crossSigned: true,
        transit: true,
      ),
    ], await hierarchy(unlistedName, rsa: false));
  }
}
