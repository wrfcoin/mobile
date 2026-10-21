class TelemetryRedactor {
  static const _redacted = '[REDACTED]';
  static const _sensitiveFragments = <String>[
    'privatekey',
    'seed',
    'mnemonic',
    'token',
    'authorization',
    'signature',
    'walletaddress',
    'address',
    'latitude',
    'longitude',
    'location',
    'memo',
    'password',
    'secret',
    'apikey',
  ];
  static final _walletAddressPattern = RegExp(
    r'\b(?:wrf[a-zA-Z0-9]{10,}|0x[a-fA-F0-9]{40})\b',
  );
  // Any run of 64 or more hex digits: keys, 128-hex signatures, digests.
  static final _privateKeyPattern = RegExp(
    r'(?<![0-9a-fA-F])(?:0x)?[0-9a-fA-F]{64,}(?![0-9a-fA-F])',
  );
  static final _jwtPattern = RegExp(
    r'\beyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9._-]{10,}\.[a-zA-Z0-9._-]{10,}\b',
  );
  static final _bearerTokenPattern = RegExp(
    r'\bbearer\s+[a-z0-9\-._~+/]+=*\b',
    caseSensitive: false,
  );
  // 12 or more BIP-39-shaped words (3-8 letters) separated by whitespace, commas,
  // semicolons, quotes or brackets in any mix (so JSON-encoded and quoted lists
  // match too), or by JSON-escaped separators written as text (a backslash then
  // n, r or t, or \\u0020), anywhere in a string.
  static final _mnemonicOnlyPattern = RegExp(
    r'''(?:(?<![A-Za-z])|(?<=\\[nrt]))[a-z]{3,8}(?:(?:[\s,;"'\[\]]|\\[nrt"']|\\u0020)+[a-z]{3,8}){11,}(?![A-Za-z])''',
    caseSensitive: false,
  );
  // `?name=value` / `&name=value` where the NAME is a secret-like word at a
  // segment boundary (token, key, secret, auth, sig, password ...): the opaque
  // VALUE is redacted, the name stays so the report is still readable.
  static final _queryParamPattern = RegExp(
    r'([?&;])([A-Za-z0-9_.\-%]+)=([^&\s#]+)',
  );
  static final _secretParamName = RegExp(
    r'^(?:[A-Za-z0-9_.\-]*[_.\-])?(?:api|access|refresh|auth|client|private|secret)?'
    r'(?:token|key|secret|authorization|auth|sig|signature|password|passwd)'
    r'(?:[_.\-][A-Za-z0-9_.\-]*)?$',
    caseSensitive: false,
  );
  // Two adjacent decimals with 2+ places (finer than 0.1 degree) read as a
  // coordinate pair; labelled lat/lon values at 2+ places are redacted too.
  static final _coordinatePairPattern = RegExp(
    r'(?<![\w.])-?\d{1,3}\.\d{2,}(?:\s*[,;]\s*|\s+)-?\d{1,3}\.\d{2,}(?![\w.])',
  );
  static final _labelledCoordinatePattern = RegExp(
    r'''(\b(?:lat|latitude|lon|long|longitude|lng)\b["']?\s*[:=]?\s*)[-+]?\d*\.\d{2,}''',
    caseSensitive: false,
  );
  static final _preciseDecimalPattern = RegExp(
    r'(?<![\w.])-?(?:\d{1,3}\.\d{3,}(?:[eE][+-]?\d+)?|\d+(?:\.\d+)?[eE][+-]?\d+)(?![\w.])',
  );

  static Map<String, dynamic> redactMap(Map<String, dynamic> payload) {
    return payload.map(
      (key, value) => MapEntry<String, dynamic>(
        _redactString(key),
        _redactValue(key, value),
      ),
    );
  }

  static dynamic _redactValue(String key, dynamic value) {
    if (_isSensitiveKey(key)) return _redacted;
    if (value is String) return _redactString(value);
    if (value is Map<String, dynamic>) return redactMap(value);
    if (value is Map) {
      return value.map(
        (nestedKey, nestedValue) => MapEntry<String, dynamic>(
          _redactString(nestedKey.toString()),
          _redactValue(nestedKey.toString(), nestedValue),
        ),
      );
    }
    if (value is Iterable) {
      // Check the list as a phrase BEFORE per-item recursion, where each word
      // would be seen alone. A non-string item breaks a run.
      final joined = value.map((e) => e is String ? e : '|').join(' ');
      if (_mnemonicOnlyPattern.hasMatch(joined)) return _redacted;
      return value
          .map((item) => _redactValue(key, item))
          .toList(growable: false);
    }
    return value;
  }

  static String _redactString(String value) {
    if (value.isEmpty) return value;

    return value
        .replaceAll(_walletAddressPattern, _redacted)
        .replaceAll(_privateKeyPattern, _redacted)
        .replaceAll(_jwtPattern, _redacted)
        .replaceAll(_bearerTokenPattern, _redacted)
        .replaceAllMapped(_queryParamPattern, (m) {
          final name = m.group(2)!;
          // Classify the DECODED name (tok%65n is token); the whole original
          // value is replaced and never decoded or re-emitted. A malformed
          // escape is classified by its raw name.
          return _secretParamName.hasMatch(_decodedName(name))
              ? '${m.group(1)}$name=$_redacted'
              : m.group(0)!;
        })
        .replaceAll(_mnemonicOnlyPattern, _redacted)
        .replaceAll(_coordinatePairPattern, _redacted)
        .replaceAllMapped(
          _labelledCoordinatePattern,
          (m) => '${m.group(1)}$_redacted',
        )
        .replaceAll(_preciseDecimalPattern, _redacted);
  }

  static String _decodedName(String name) {
    if (!name.contains('%')) return name;
    try {
      return Uri.decodeQueryComponent(name);
    } catch (_) {
      return name;
    }
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized == 'to' || normalized == 'from') return true;
    return _sensitiveFragments.any(normalized.contains);
  }
}
