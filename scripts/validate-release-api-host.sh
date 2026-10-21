#!/usr/bin/env bash
# Fail-closed gate for the API base URL baked into a distributable build.
# Admits only https with a canonical, multi-label public DNS name that resolves
# to a non-loopback address. There is deliberately no test hook here: the gate
# tests inject a stub `getent` through PATH instead.
set -euo pipefail

api_url="${1:-${WRFCOIN_API_BASE_URL:-}}"
if [[ -z "$api_url" ]]; then
  echo "WRFCOIN_API_BASE_URL is required for release builds" >&2
  exit 1
fi
if [[ "$api_url" != https://* ]]; then
  echo "WRFCOIN_API_BASE_URL must use https" >&2
  exit 1
fi

authority="${api_url#https://}"
authority="${authority%%/*}"
authority="${authority%%\?*}"
authority="${authority%%#*}"
if [[ -z "$authority" || "$authority" == *"@"* ]]; then
  echo "WRFCOIN_API_BASE_URL has no valid host" >&2
  exit 1
fi

# Bracketed hosts are IPv6 literals (any spelling of ::1 included).
if [[ "$authority" == \[* ]]; then
  echo "IP literal API host rejected: $authority (use a DNS name)" >&2
  exit 1
fi

host="${authority%%:*}"
host="$(tr '[:upper:]' '[:lower:]' <<<"$host")"
# One trailing dot is the absolute form of the same name ("localhost.").
host="${host%.}"

# Strict LDH: rejects empty labels ("localhost.."), percent-encoding,
# underscores and anything else a resolver might normalize differently.
label='[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?'
if [[ ${#host} -gt 253 || ! "$host" =~ ^${label}(\.${label})*$ ]]; then
  echo "WRFCOIN_API_BASE_URL has no valid host: $host" >&2
  exit 1
fi

# Single-label names are local by construction ("localhost", "2130706433").
if [[ "$host" != *.* ]]; then
  echo "LOCAL API host rejected: $host (not a fully qualified name)" >&2
  exit 1
fi

# A numeric or hex final label means an IPv4 literal in any inet_aton
# spelling: 127.0.0.1, 127.1, 0x7f.1, 0177.0.0.1.
tld="${host##*.}"
if [[ "$tld" =~ ^[0-9]+$ || "$tld" =~ ^0x[0-9a-f]*$ ]]; then
  echo "IP literal API host rejected: $host (use a DNS name)" >&2
  exit 1
fi

case "$host" in
  api.wrfcoin.app|api.wrfcoin.org|api.wrfcoin.network|example.com|w3bstream.example.com)
    echo "PLACEHOLDER API host rejected: $host" >&2
    exit 1
    ;;
  *.localhost|*.local|*.invalid|*.test|*.example|*.internal|*.home.arpa)
    echo "LOCAL API host rejected: $host (reserved suffix)" >&2
    exit 1
    ;;
esac

resolve_addresses() {
  if command -v getent >/dev/null 2>&1; then
    getent hosts "$host" | awk '{print $1}'
  elif command -v dscacheutil >/dev/null 2>&1; then
    dscacheutil -q host -a name "$host" | awk '/^ip(v6)?_address:/ {print $2}'
  elif command -v host >/dev/null 2>&1; then
    host "$host" | awk '/has (IPv6 )?address/ {print $NF}'
  else
    echo "No supported DNS resolver is installed" >&2
    return 1
  fi
}

addresses="$(resolve_addresses || true)"
if [[ -z "$addresses" ]]; then
  echo "UNRESOLVABLE API host: $host" >&2
  exit 1
fi

while read -r addr; do
  addr="$(tr '[:upper:]' '[:lower:]' <<<"$addr")"
  case "$addr" in
    127.*|0.*|::1|::|::ffff:127.*|::ffff:0.*|0:0:0:0:0:0:0:1|0:0:0:0:0:0:0:0)
      echo "LOCAL API host rejected: $host resolves to $addr" >&2
      exit 1
      ;;
  esac
done <<<"$addresses"

echo "API_HOST_OK host=$host"
