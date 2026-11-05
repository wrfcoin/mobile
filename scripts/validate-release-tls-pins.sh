#!/usr/bin/env bash
# A release build must name a known TLS pin set (WRFCOIN_TLS_PIN_SET). The
# known names are the keys of tlsPinSets in the Dart source, so this gate and
# the app's start-up check agree. See docs/RELEASING.md#tls-pins.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$repo_root/lib/services/api/tls_pin_configuration.dart"
pin_set="${WRFCOIN_TLS_PIN_SET:-}"

if [[ -n "${WRFCOIN_TLS_PIN_SHA256_CURRENT:-}${WRFCOIN_TLS_PIN_SHA256_NEXT:-}" ]]; then
  echo "WRFCOIN_TLS_PIN_SHA256_CURRENT/_NEXT are retired; set WRFCOIN_TLS_PIN_SET instead" >&2
  exit 1
fi
if [[ -z "$pin_set" ]]; then
  echo "WRFCOIN_TLS_PIN_SET is required for release" >&2
  exit 1
fi

known_sets="$(sed -nE "s/^  '([a-z0-9.-]+)': \[$/\1/p" "$source_file")"
if [[ -z "$known_sets" ]]; then
  echo "no TLS pin sets found in $source_file" >&2
  exit 1
fi
if ! grep -qxF -- "$pin_set" <<<"$known_sets"; then
  echo "WRFCOIN_TLS_PIN_SET names an unknown pin set (known: $(tr '\n' ' ' <<<"$known_sets"))" >&2
  exit 1
fi

echo "release TLS pin set valid: $pin_set"
