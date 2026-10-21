#!/usr/bin/env bash
# Gate tests for build_profile_apk.sh. Runs a copy of the script in a scratch
# repo against stub getent / flutter / javac / apksigner, so nothing is built
# and no network is touched. Each RED case asserts WHICH gate refused.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
mkdir -p "$repo/scripts" "$work/bin" "$work/jdk/bin" "$work/sdk/platforms/android-36" "$work/sdk/build-tools/36.0.0"
cp "$here/build_profile_apk.sh" "$here/validate-release-api-host.sh" "$repo/scripts/"
chmod +x "$repo/scripts/"*.sh

good_url="https://release-api.wrfcoin-ci-fixture.net/api"
cat >"$work/bin/getent" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  release-api.wrfcoin-ci-fixture.net|round6-nonexistent.invalid) echo "203.0.113.10   $2" ;;
  *) exit 2 ;;
esac
EOF
# Records that a build was attempted (and its arguments), then produces a fake APK.
cat >"$work/bin/flutter" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FLUTTER_MARKER"
mkdir -p build/app/outputs/flutter-apk
echo fake-apk >build/app/outputs/flutter-apk/app-profile.apk
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$work/jdk/bin/javac"
chmod +x "$work/bin/getent" "$work/bin/flutter" "$work/jdk/bin/javac"

apksigner="$work/sdk/build-tools/36.0.0/apksigner"
install_apksigner() {
  cat >"$apksigner" <<'EOF'
#!/usr/bin/env bash
case "$STUB_SIGNER" in
  debug) echo "Signer #1 certificate DN: C=US, O=Android, CN=Android Debug" ;;
  release) echo "Signer #1 certificate DN: CN=WRFCoin Release, O=WRFCoin" ;;
  lookalike) echo "Signer #1 certificate DN: C=US, O=Android, CN=Android Debugger" ;;
  two) printf '%s\n' "Signer #1 certificate DN: C=US, O=Android, CN=Android Debug" \
         "Signer #2 certificate DN: CN=Someone Else" ;;
  verify-fails) echo "DOES NOT VERIFY" >&2; exit 1 ;;
esac
EOF
  chmod +x "$apksigner"
}

log="$work/log"
export FLUTTER_MARKER="$work/flutter-ran"

# run <expect: ok|refused> <label> <pattern> <url> [env...]
run() {
  local expect="$1" label="$2" pattern="$3" url="$4"
  shift 4
  rm -f "$FLUTTER_MARKER" "$repo/build/app/outputs/flutter-apk/app-profile.apk"
  local rc=0
  local chain_env=(WRFCOIN_CHAIN_ID=888)
  if [[ "$label" == "unset chain" ]]; then chain_env=(); fi
  env -u WRFCOIN_CHAIN_ID -u API_HOST_RESOLVER_OVERRIDE -u WRFCOIN_WALLET_AUTH_ORIGIN PATH="$work/bin:$PATH" JAVA_HOME="$work/jdk" \
    ANDROID_HOME="$work/sdk" ANDROID_SDK_ROOT= STUB_SIGNER=debug "${chain_env[@]}" "$@" \
    bash "$repo/scripts/build_profile_apk.sh" "$url" >"$log" 2>&1 || rc=$?
  if [[ "$expect" == ok ]]; then
    [[ "$rc" == 0 ]] || { echo "FAIL: $label exited $rc" >&2; cat "$log" >&2; exit 1; }
  else
    [[ "$rc" != 0 ]] || { echo "FAIL: $label unexpectedly succeeded" >&2; cat "$log" >&2; exit 1; }
    if grep -Eq '^(PROFILE_APK_OK|SHA256=|APK=)' "$log"; then
      echo "FAIL: $label reported a build result before refusing" >&2
      exit 1
    fi
  fi
  if ! grep -Eq "$pattern" "$log"; then
    echo "FAIL: $label: output lacks /$pattern/:" >&2
    cat "$log" >&2
    exit 1
  fi
  echo "${expect^^} ok: $label"
}

install_apksigner

run refused "unset chain" 'WRFCOIN_CHAIN_ID is required' "$good_url"
[[ ! -e "$FLUTTER_MARKER" ]] || { echo "FAIL: flutter ran without chain"; exit 1; }
run refused "blank chain" 'WRFCOIN_CHAIN_ID is required' "$good_url" WRFCOIN_CHAIN_ID=
[[ ! -e "$FLUTTER_MARKER" ]] || { echo "FAIL: flutter ran with blank chain"; exit 1; }
for chain in 777 888; do
  run ok "explicit chain $chain" '^PROFILE_APK_OK$' "$good_url" WRFCOIN_CHAIN_ID="$chain"
  grep -qxF -- "--dart-define=WRFCOIN_CHAIN_ID=$chain" "$FLUTTER_MARKER"
done

# URL gate. ANDROID_HOME is empty, so a URL that slipped through would be
# refused by the SDK gate instead; the pattern pins the refusal to the URL gate.
url_red() {
  run refused "$1" '^BUILD_PROFILE_APK_REFUSED: API base URL rejected' "$2" ANDROID_HOME= "${@:3}"
  if grep -q 'ANDROID_HOME' "$log"; then
    echo "FAIL: $1 reached the SDK gate" >&2
    exit 1
  fi
}
# Control first, so the RED cases below cannot pass vacuously: the same URL gate admits the fixture host, which then stops at the SDK gate.
run refused "good URL reaches SDK gate" 'ANDROID_HOME / ANDROID_SDK_ROOT is not set' "$good_url" ANDROID_HOME=
url_red "retired resolver override + .invalid" "https://round6-nonexistent.invalid/api" \
  API_HOST_RESOLVER_OVERRIDE=round6-nonexistent.invalid
url_red "localhost. trailing dot" "https://localhost./api"
url_red "127.1 short IPv4" "https://127.1/api"
url_red "expanded IPv6 loopback" "https://[0:0:0:0:0:0:0:1]/api"
url_red "http scheme" "http://release-api.wrfcoin-ci-fixture.net/api"

# Signer gate: a missing or non-executable apksigner is refused BEFORE building.
chmod -x "$apksigner"
run refused "apksigner not executable" 'no executable apksigner' "$good_url"
[[ ! -e "$FLUTTER_MARKER" ]] || { echo "FAIL: flutter ran without apksigner" >&2; exit 1; }
rm -f "$apksigner"
run refused "apksigner missing" 'no executable apksigner' "$good_url"
[[ ! -e "$FLUTTER_MARKER" ]] || { echo "FAIL: flutter ran without apksigner" >&2; exit 1; }
install_apksigner

# Verification must pass before anything is reported as built.
run refused "apksigner verify fails" 'apksigner verify failed' "$good_url" STUB_SIGNER=verify-fails
run refused "release signer" 'not debug-signed' "$good_url" STUB_SIGNER=release
run refused "lookalike CN=Android Debugger" 'not debug-signed' "$good_url" STUB_SIGNER=lookalike
run refused "two signers" 'exactly one APK signer' "$good_url" STUB_SIGNER=two
run ok "debug signer" '^PROFILE_APK_OK$' "$good_url"
grep -q '^SHA256=[0-9a-f]\{64\}$' "$log"
if grep -q 'WRFCOIN_WALLET_AUTH_ORIGIN' "$FLUTTER_MARKER"; then
  echo "FAIL: portless URL without an origin passed an auth-origin define" >&2
  exit 1
fi

# Wallet-login origin gate (mobile#44 / infra#1062 tailnet :9444 route). The app
# derives the login origin from the API URL, so a ported API URL must name the
# backend's origin explicitly. Refusals happen before the SDK gate.
port_url="https://release-api.wrfcoin-ci-fixture.net:9444/api"
good_origin="https://release-api.wrfcoin-ci-fixture.net"
origin_red() {
  run refused "$1" "^BUILD_PROFILE_APK_REFUSED: $2" "$3" ANDROID_HOME= "${@:4}"
  if grep -q 'ANDROID_HOME' "$log"; then
    echo "FAIL: $1 reached the SDK gate" >&2
    exit 1
  fi
}
origin_red "ported URL without origin" 'API base URL has an explicit port' "$port_url"
origin_red "origin with a path" 'WRFCOIN_WALLET_AUTH_ORIGIN must be an https origin' "$port_url" \
  WRFCOIN_WALLET_AUTH_ORIGIN="$good_origin/api"
origin_red "origin with trailing slash" 'WRFCOIN_WALLET_AUTH_ORIGIN must be an https origin' "$port_url" \
  WRFCOIN_WALLET_AUTH_ORIGIN="$good_origin/"
origin_red "http origin" 'WRFCOIN_WALLET_AUTH_ORIGIN must be an https origin' "$port_url" \
  WRFCOIN_WALLET_AUTH_ORIGIN="http://release-api.wrfcoin-ci-fixture.net"
origin_red "localhost origin" 'WRFCOIN_WALLET_AUTH_ORIGIN rejected' "$port_url" \
  WRFCOIN_WALLET_AUTH_ORIGIN="https://localhost"
run ok "ported URL with explicit origin" '^PROFILE_APK_OK$' "$port_url" \
  WRFCOIN_WALLET_AUTH_ORIGIN="$good_origin"
grep -qxF -- "--dart-define=WRFCOIN_WALLET_AUTH_ORIGIN=$good_origin" "$FLUTTER_MARKER" ||
  { echo "FAIL: explicit origin was not passed to flutter" >&2; cat "$FLUTTER_MARKER" >&2; exit 1; }
grep -qxF -- "--dart-define=API_BASE_URL=$port_url" "$FLUTTER_MARKER" ||
  { echo "FAIL: API URL was not passed to flutter" >&2; exit 1; }
grep -qxF "WALLET_AUTH_ORIGIN=$good_origin" "$log"

echo "build_profile_apk gate: URL, auth-origin and signer gates fail closed; debug-signed stub build GREEN"
