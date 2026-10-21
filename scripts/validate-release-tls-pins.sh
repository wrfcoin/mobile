#!/usr/bin/env bash
set -euo pipefail

current_pin="${WRFCOIN_TLS_PIN_SHA256_CURRENT:-}"
next_pin="${WRFCOIN_TLS_PIN_SHA256_NEXT:-}"
pin_pattern='^([0-9A-Fa-f]{64}|([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2})$'

if [[ -z "$current_pin" ]]; then
  echo "WRFCOIN_TLS_PIN_SHA256_CURRENT is required for release" >&2
  exit 1
fi
if [[ ! "$current_pin" =~ $pin_pattern ]] || [[ "$current_pin" =~ CONFIGURE|PLACEHOLDER|CHANGEME ]]; then
  echo "WRFCOIN_TLS_PIN_SHA256_CURRENT is malformed or a placeholder" >&2
  exit 1
fi
if [[ -n "$next_pin" ]] && [[ ! "$next_pin" =~ $pin_pattern ]]; then
  echo "WRFCOIN_TLS_PIN_SHA256_NEXT is malformed or a placeholder" >&2
  exit 1
fi

normalize_pin() { tr -d ':' <<<"$1" | tr '[:lower:]' '[:upper:]'; }
if [[ -n "$next_pin" ]] && [[ "$(normalize_pin "$current_pin")" == "$(normalize_pin "$next_pin")" ]]; then
  echo "Current and next TLS pins must be distinct" >&2
  exit 1
fi

echo "release TLS pin configuration valid"
