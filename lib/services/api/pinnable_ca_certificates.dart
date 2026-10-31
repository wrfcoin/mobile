/// CA certificates a release build can pin, as base64 DER.
///
/// A pin (`TLS_PIN_SHA256_CURRENT` / `_NEXT`) is the SHA-256 of a certificate's
/// SubjectPublicKeyInfo. dart:io shows the app only the leaf certificate, so
/// the app cannot hash the intermediates the server sends. Instead each pin
/// selects the bundled certificate with that key, and that certificate becomes
/// the ONLY trust anchor: the TLS stack then accepts a chain only if it runs
/// from the leaf to a pinned certificate, with every signature, the validity
/// dates and the host name checked. A pin with no certificate here is refused
/// at start-up (fail closed). To pin another CA, add its certificate here.
///
/// These are public certificates; the SPKI pin for each is in the comment and
/// in docs/RELEASING.md. Sources: the chain wrfcoin.com served on 2026-10-31
/// and https://pki.goog/repository/.
library;

class PinnableCaCertificate {
  const PinnableCaCertificate(this.name, this.derBase64);

  final String name;
  final String derBase64;
}

/// GTS WE1 (intermediate; issued by GTS Root R4; expires 2029-02-20).
/// SPKI SHA-256: `908769e8d34477cc2cba0632c88605b22d7294c0840f78596d247c645b1afc0e`
const PinnableCaCertificate gtsWe1 = PinnableCaCertificate(
  'GTS WE1',
  'MIICnzCCAiWgAwIBAgIQf/MZd5csIkp2FV0TttaF4zAKBggqhkjOPQQDAzBHMQsw'
      'CQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEU'
      'MBIGA1UEAxMLR1RTIFJvb3QgUjQwHhcNMjMxMjEzMDkwMDAwWhcNMjkwMjIwMTQw'
      'MDAwWjA7MQswCQYDVQQGEwJVUzEeMBwGA1UEChMVR29vZ2xlIFRydXN0IFNlcnZp'
      'Y2VzMQwwCgYDVQQDEwNXRTEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARvzTr+'
      'Z1dHTCEDhUDCR127WEcPQMFcF4XGGTfn1XzthkubgdnXGhOlCgP4mMTG6J7/EFmP'
      'LCaY9eYmJbsPAvpWo4H+MIH7MA4GA1UdDwEB/wQEAwIBhjAdBgNVHSUEFjAUBggr'
      'BgEFBQcDAQYIKwYBBQUHAwIwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU'
      'kHeSNWfE/6jMqeZ72YB5e8yT+TgwHwYDVR0jBBgwFoAUgEzW63T/STaj1dj8tT7F'
      'avCUHYwwNAYIKwYBBQUHAQEEKDAmMCQGCCsGAQUFBzAChhhodHRwOi8vaS5wa2ku'
      'Z29vZy9yNC5jcnQwKwYDVR0fBCQwIjAgoB6gHIYaaHR0cDovL2MucGtpLmdvb2cv'
      'ci9yNC5jcmwwEwYDVR0gBAwwCjAIBgZngQwBAgEwCgYIKoZIzj0EAwMDaAAwZQIx'
      'AOcCq1HW90OVznX+0RGU1cxAQXomvtgM8zItPZCuFQ8jSBJSjz5keROv9aYsAm5V'
      'sQIwJonMaAFi54mrfhfoFNZEfuNMSQ6/bIBiNLiyoX46FohQvKeIoJ99cx7sUkFN'
      '7uJW',
);

/// GTS WR1 (intermediate; issued by GTS Root R1; expires 2029-02-20).
/// SPKI SHA-256: `c83bbda20db9e4d3791847fe0706bdad3aea150d04c9d674af514287d4dd016e`
const PinnableCaCertificate gtsWr1 = PinnableCaCertificate(
  'GTS WR1',
  'MIIFCzCCAvOgAwIBAgIQf9niwtIEigR0tieibQhopzANBgkqhkiG9w0BAQsFADBH'
      'MQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExM'
      'QzEUMBIGA1UEAxMLR1RTIFJvb3QgUjEwHhcNMjMxMjEzMDkwMDAwWhcNMjkwMjIw'
      'MTQwMDAwWjA7MQswCQYDVQQGEwJVUzEeMBwGA1UEChMVR29vZ2xlIFRydXN0IFNl'
      'cnZpY2VzMQwwCgYDVQQDEwNXUjEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK'
      'AoIBAQDPbjYWircr7kaYAx1TcA937qNLoHK+jyMtwkfGj1yN+T3mGo7uMyINyRFI'
      'uLBizvRpDXICfd7VJg/DbpvPfg7XIM/GkDujggbaOp3/bFa/3OlhlEXkabxPD8kT'
      'wK1hRHIggdAPK55oamJqj4oiV3lpK+IkM352YyxdvFFpfiMHsf92gfHuuFi1azUV'
      '76HmSCg5lzHZBx+Vp56uz5i8no2KA+Gwl01Qb5NMSh/4233xkJkVf+OW7e4xgepy'
      'PVId3yVkpQtwqp7oqLlHyKdaECVgb0Lh1z/njwzwwoNGMyDmS3cEdqFop10VGO/Y'
      'KHc1rQ6tRuRibuKq+MzvN34PJrMHAgMBAAGjgf4wgfswDgYDVR0PAQH/BAQDAgGG'
      'MB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjASBgNVHRMBAf8ECDAGAQH/'
      'AgEAMB0GA1UdDgQWBBRmaUnU3iqckQPPiQ4kuA4wA26ILjAfBgNVHSMEGDAWgBTk'
      'rysmcRorSCeFL1JmLO/wiRNxPjA0BggrBgEFBQcBAQQoMCYwJAYIKwYBBQUHMAKG'
      'GGh0dHA6Ly9pLnBraS5nb29nL3IxLmNydDArBgNVHR8EJDAiMCCgHqAchhpodHRw'
      'Oi8vYy5wa2kuZ29vZy9yL3IxLmNybDATBgNVHSAEDDAKMAgGBmeBDAECATANBgkq'
      'hkiG9w0BAQsFAAOCAgEATuazCBEgkWAn+VGQTQIY7rjBidUihJfm1t/mTjo7KQR+'
      '3iDx4o2L06oeF0Q3wpKYpQgI/TeMqUlYMWQmZbWPE0PX8pfsVAE5E5tVOjh34bNA'
      'JwDPVnsZVJwzN3nw5BGQ7sxRspFzIcM/qbbTpNeXf9II4Wsk2+Tv6FSVFZUL3/0u'
      'HradbruDWjRQ4IZ7mYqKiEqk08dpOZ+TmBzwykEGy1/IXberb6Ap1SSnn2+RI7t6'
      'N/fqPCrwwFjp8kg1G6etRATGBaPYCx+GjJMFPX+k97Alvoj3/98SvqdegLPYEPjv'
      'xUclHpiKLD63NMmVarVQddIL6kOvTe5k0pnxRnR+mndGHIQc77TLbcZFeja56Pyn'
      'lSqmer578c7CBrPqo1BVmPyWUK+v6sGuzs7Mq7QQaxVs4710cI/MpPp1ovxMVt17'
      'ENKxLk34LpEKAKVmqwnzbHHRjhXNeCC984XDOwLEp0K4MzHl8ZOWJQAakCdVlFC+'
      'PyA3GP2JX/QLoqWNHGuN9c9vLObDhHVs/L+65De+OdnnjpFGI9xxtsNyRsyaHdFA'
      'f5z7ulOoXDXkHCCej/Ehs5docReNt16W2xbH/EBuirJrOzFE2rtALxksl1TdEjOf'
      'IKXOJfUqQeVI5+hA7V+n1+A/n7Npg0S+5ODytWh5XW54ccN1drJnMK54ttozh0c=',
);

/// GTS Root R4 (self-signed root; expires 2036-06-22).
/// SPKI SHA-256: `9847e5653e5e9e847516e5cb818606aa7544a19be67fd7366d506988e8d84347`
const PinnableCaCertificate gtsRootR4 = PinnableCaCertificate(
  'GTS Root R4',
  'MIICCTCCAY6gAwIBAgINAgPlwGjvYxqccpBQUjAKBggqhkjOPQQDAzBHMQswCQYD'
      'VQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEUMBIG'
      'A1UEAxMLR1RTIFJvb3QgUjQwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAw'
      'WjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2Vz'
      'IExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjQwdjAQBgcqhkjOPQIBBgUrgQQAIgNi'
      'AATzdHOnaItgrkO4NcWBMHtLSZ37wWHO5t5GvWvVYRg1rkDdc/eJkTBa6zzuhXyi'
      'QHY7qca4R9gq55KRanPpsXI5nymfopjTX15YhmUPoYRlBtHci8nHc8iMai/lxKvR'
      'HYqjQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW'
      'BBSATNbrdP9JNqPV2Py1PsVq8JQdjDAKBggqhkjOPQQDAwNpADBmAjEA6ED/g94D'
      '9J+uHXqnLrmvT/aDHQ4thQEd0dlq7A/Cr8deVl5c1RxYIigL9zC2L7F8AjEA8GE8'
      'p/SgguMh1YQdc4acLa/KNJvxn7kjNuK8YAOdgLOaVsjh4rsUecrNIdSUtUlD',
);

/// GTS Root R1 (self-signed root; expires 2036-06-22).
/// SPKI SHA-256: `871a9194f4eed5b312ff40c84c1d524aed2f778bbff25f138cf81f680a7adc67`
const PinnableCaCertificate gtsRootR1 = PinnableCaCertificate(
  'GTS Root R1',
  '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'
      'bP6MvPJwNQzcmRk13NfIRmPVNnGuV/u3gm3c',
);

const List<PinnableCaCertificate> pinnableCaCertificates = [
  gtsWe1,
  gtsWr1,
  gtsRootR4,
  gtsRootR1,
];
