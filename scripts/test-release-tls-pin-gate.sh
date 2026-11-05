#!/usr/bin/env bash
set -euo pipefail

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

unset WRFCOIN_TLS_PIN_SET WRFCOIN_TLS_PIN_SHA256_CURRENT WRFCOIN_TLS_PIN_SHA256_NEXT
export RELEASE_IOS=false
export RELEASE_ANDROID=false

expect_refused() {
  local reason="$1"
  if bash scripts/validate-release-tls-pins.sh >"$log_file" 2>&1; then
    echo "expected release verification to refuse: $reason" >&2
    exit 1
  fi
  if ! grep -qF "$reason" "$log_file"; then
    echo "release verification failed for the wrong reason (wanted: $reason)" >&2
    cat "$log_file" >&2
    exit 1
  fi
}

expect_refused "WRFCOIN_TLS_PIN_SET is required for release"

export WRFCOIN_TLS_PIN_SET="cloudflare-universal-v0"
expect_refused "unknown pin set"

export WRFCOIN_TLS_PIN_SET="cloudflare-universal-v1"
export WRFCOIN_TLS_PIN_SHA256_CURRENT="9847e5653e5e9e847516e5cb818606aa7544a19be67fd7366d506988e8d84347"
expect_refused "retired"
unset WRFCOIN_TLS_PIN_SHA256_CURRENT

bash scripts/validate-release-tls-pins.sh >/dev/null

echo "release TLS pin gate: missing, unknown and retired pin config RED confirmed"
