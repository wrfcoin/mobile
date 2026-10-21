#!/usr/bin/env bash
set -euo pipefail

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

unset WRFCOIN_TLS_PIN_SHA256_CURRENT WRFCOIN_TLS_PIN_SHA256_NEXT
export RELEASE_IOS=false
export RELEASE_ANDROID=false

if bash scripts/validate-release-tls-pins.sh >"$log_file" 2>&1; then
  echo "expected release verification to reject missing TLS pins" >&2
  exit 1
fi

if ! grep -q "WRFCOIN_TLS_PIN_SHA256_CURRENT is required for release" "$log_file"; then
  echo "release verification failed for the wrong reason" >&2
  cat "$log_file" >&2
  exit 1
fi

export WRFCOIN_TLS_PIN_SHA256_CURRENT="000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F"
export WRFCOIN_TLS_PIN_SHA256_NEXT="202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F"
bash scripts/validate-release-tls-pins.sh >/dev/null

echo "release TLS pin gate: missing-pin RED confirmed"
