#!/usr/bin/env bash
# Gate tests for validate-release-api-host.sh. DNS is injected with a stub
# `getent` on PATH (the validator itself has no test hook). Every RED case
# asserts the specific rejection, so a case cannot pass by failing elsewhere.
set -euo pipefail

validator="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate-release-api-host.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
log_file="$work/log"

# Stub resolver: "host=addr" pairs in STUB_HOSTS; anything else is NXDOMAIN.
mkdir -p "$work/bin"
cat >"$work/bin/getent" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == hosts ]] || exit 2
for pair in ${STUB_HOSTS:-}; do
  if [[ "${pair%%=*}" == "$2" ]]; then
    echo "${pair#*=}   $2"
    exit 0
  fi
done
exit 2
EOF
chmod +x "$work/bin/getent"

export STUB_HOSTS="release-api.wrfcoin-ci-fixture.net=203.0.113.10 \
loopback.wrfcoin-ci-fixture.net=127.0.0.1 \
loopback6.wrfcoin-ci-fixture.net=::1 \
round6-nonexistent.invalid=203.0.113.11 \
localhost=203.0.113.12 \
api.wrfcoin.app=203.0.113.13"

run_validator() {
  PATH="$work/bin:$PATH" bash "$validator" "$@"
}

expect_red() {
  local label="$1" url="$2" pattern="$3"
  shift 3
  if env "$@" PATH="$work/bin:$PATH" bash "$validator" "$url" >"$log_file" 2>&1; then
    echo "FAIL: $label unexpectedly passed" >&2
    cat "$log_file" >&2
    exit 1
  fi
  if ! grep -Eq "$pattern" "$log_file"; then
    echo "FAIL: $label rejected for the wrong reason (wanted /$pattern/):" >&2
    cat "$log_file" >&2
    exit 1
  fi
  echo "RED ok: $label"
}

expect_red "unset URL" "" "is required"
expect_red "HTTP URL" "http://release-api.wrfcoin-ci-fixture.net/api" "must use https"
expect_red "userinfo" "https://user@release-api.wrfcoin-ci-fixture.net/api" "no valid host"
expect_red "placeholder URL" "https://api.wrfcoin.app/api" "PLACEHOLDER"
expect_red "unresolvable URL" "https://does-not-resolve.wrfcoin-ci-fixture.net/api" "UNRESOLVABLE"
expect_red "localhost" "https://localhost/api" "LOCAL API host"
expect_red "LOCALHOST uppercase" "https://LOCALHOST/api" "LOCAL API host"
expect_red "localhost. trailing dot" "https://localhost./api" "LOCAL API host"
expect_red "localhost.. empty label" "https://localhost../api" "no valid host"
expect_red "sub.localhost" "https://api.localhost/api" "reserved suffix"
expect_red "mdns .local" "https://phone.local/api" "reserved suffix"
expect_red ".local. trailing dot" "https://phone.local./api" "reserved suffix"
expect_red "percent-encoded host" "https://local%68ost.wrfcoin-ci-fixture.net/api" "no valid host"
expect_red "IPv4 dotted" "https://127.0.0.1/api" "IP literal"
expect_red "IPv4 short 127.1" "https://127.1/api" "IP literal"
expect_red "IPv4 hex 0x7f.1" "https://0x7f.1/api" "IP literal"
expect_red "IPv4 octal" "https://0177.0.0.1/api" "IP literal"
expect_red "IPv4 decimal" "https://2130706433/api" "LOCAL API host"
expect_red "IPv4 with port" "https://127.0.0.1:4001/api" "IP literal"
expect_red "IPv6 ::1" "https://[::1]/api" "IP literal"
expect_red "IPv6 expanded loopback" "https://[0:0:0:0:0:0:0:1]:443/api" "IP literal"
expect_red "IPv4-mapped IPv6" "https://[::ffff:127.0.0.1]/api" "IP literal"
expect_red "resolves to 127.0.0.1" "https://loopback.wrfcoin-ci-fixture.net/api" "resolves to 127"
expect_red "resolves to ::1" "https://loopback6.wrfcoin-ci-fixture.net/api" "resolves to ::1"
# The retired API_HOST_RESOLVER_OVERRIDE hook must stay dead, and .invalid is
# rejected even when something does resolve it.
expect_red "retired resolver override" "https://round6-nonexistent.invalid/api" "reserved suffix" \
  API_HOST_RESOLVER_OVERRIDE=round6-nonexistent.invalid

run_validator "https://release-api.wrfcoin-ci-fixture.net/api" >"$log_file"
grep -q '^API_HOST_OK host=release-api.wrfcoin-ci-fixture.net$' "$log_file"
run_validator "https://Release-API.wrfcoin-ci-fixture.net.:443/api" >"$log_file"
grep -q '^API_HOST_OK host=release-api.wrfcoin-ci-fixture.net$' "$log_file"
echo "GREEN ok: public fixture host (plain, and mixed-case + trailing dot + port)"

echo "release API host gate: all invalid cases RED for the right reason; fixture host GREEN"
