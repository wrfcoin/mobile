#!/usr/bin/env bash
# Build a sideloadable, debug-signed Android PROFILE APK for testnet dogfooding.
#
# Usage: WRFCOIN_CHAIN_ID=<confirmed-chain-id> [WRFCOIN_WALLET_AUTH_ORIGIN=<https origin>] scripts/build_profile_apk.sh <https API base URL>
#   e.g. scripts/build_profile_apk.sh https://<public-api-host>/api
#   e.g. WRFCOIN_WALLET_AUTH_ORIGIN=https://<public-api-host> \
#          scripts/build_profile_apk.sh https://<public-api-host>:9444/api
#
# WRFCOIN_WALLET_AUTH_ORIGIN is the backend's single wallet-login origin. The
# app otherwise derives it from the API URL (scheme://host[:port]), so an API
# URL on a different port than the login origin (a separate API :9444 route,
# infra#1062) would build an app whose every login challenge fails to verify.
# An API URL with an explicit port is therefore refused unless the origin is
# set explicitly.
#
# Zero-cost path: no release keystore, no store upload, no network publish.
# Profile mode is used on purpose. Release mode requires
# TLS_SECURITY_PROFILE=public-release plus TLS pins (lib/main.dart,
# lib/services/api/tls_pin_configuration.dart); profile requires neither.
#
# Requires ANDROID_HOME (or ANDROID_SDK_ROOT) with build-tools (apksigner) and
# a full JDK 17+ with javac.
# A JRE-only java fails deep inside Gradle with "does not provide the
# required capabilities: [JAVA_COMPILER]".
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "BUILD_PROFILE_APK_REFUSED: $*" >&2
  exit 1
}

[[ -n "${WRFCOIN_CHAIN_ID:-}" ]] || fail "WRFCOIN_CHAIN_ID is required for profile builds"

api_url="${1:-${API_BASE_URL:-}}"
[[ -n "$api_url" ]] || fail "API base URL argument is required"
# https + canonical public DNS name: no IP literals, local/reserved or
# placeholder hosts, must resolve to a non-loopback address (shared release gate).
scripts/validate-release-api-host.sh "$api_url" || fail "API base URL rejected: $api_url"

api_authority="${api_url#https://}"
api_authority="${api_authority%%[/?#]*}"
auth_origin="${WRFCOIN_WALLET_AUTH_ORIGIN:-}"
auth_define=()
if [[ -n "$auth_origin" ]]; then
  [[ "$auth_origin" =~ ^https://[^/?#@[:space:]]+$ ]] ||
    fail "WRFCOIN_WALLET_AUTH_ORIGIN must be an https origin with no path, query or trailing slash: $auth_origin"
  scripts/validate-release-api-host.sh "$auth_origin" >/dev/null ||
    fail "WRFCOIN_WALLET_AUTH_ORIGIN rejected: $auth_origin"
  auth_define=(--dart-define=WRFCOIN_WALLET_AUTH_ORIGIN="$auth_origin")
elif [[ "$api_authority" == *:* ]]; then
  fail "API base URL has an explicit port ($api_authority); set WRFCOIN_WALLET_AUTH_ORIGIN to the backend's wallet-login origin, or every login challenge fails to verify"
fi

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$sdk" ]] || fail "ANDROID_HOME / ANDROID_SDK_ROOT is not set"
if ! compgen -G "$sdk/platforms/android-*" >/dev/null; then
  fail "no Android platform installed under $sdk/platforms"
fi
if ! compgen -G "$sdk/build-tools/*" >/dev/null; then
  fail "no Android build-tools installed under $sdk/build-tools"
fi
export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"

# Signer verification is mandatory, so require its tool before spending a build.
apksigner=""
while IFS= read -r candidate; do
  [[ -x "$candidate" ]] && apksigner="$candidate"
done < <(compgen -G "$sdk/build-tools/*/apksigner" | sort -V)
[[ -n "$apksigner" ]] || fail "no executable apksigner under $sdk/build-tools (install build-tools)"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is not installed"

javac_bin="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
command -v "$javac_bin" >/dev/null 2>&1 || fail "no javac found (set JAVA_HOME to a full JDK 17+, not a JRE)"
command -v flutter >/dev/null 2>&1 || fail "flutter is not on PATH"

# Never let release keystore material leak into a sideload build.
unset WRFCOIN_ANDROID_KEYSTORE_PATH WRFCOIN_ANDROID_KEYSTORE_PASSWORD \
  WRFCOIN_ANDROID_KEY_ALIAS WRFCOIN_ANDROID_KEY_PASSWORD

# Cap Gradle so concurrent builds on a shared workstation do not OOM
# (android/gradle.properties asks for 8G). Override with GRADLE_OPTS.
export GRADLE_OPTS="${GRADLE_OPTS:--Dorg.gradle.daemon=false -Dorg.gradle.jvmargs=-Xmx3g -Dkotlin.daemon.jvm.options=-Xmx1g}"

# The Flutter Gradle migrator rewrites android/gradle.properties on build;
# restore it afterwards when it started clean so the build leaves no diff.
props=android/gradle.properties
props_clean=0
git diff --quiet -- "$props" 2>/dev/null && props_clean=1
restore_props() {
  if [[ "$props_clean" == 1 ]]; then git checkout -q -- "$props"; fi
}
trap restore_props EXIT

flutter build apk --profile \
  --dart-define=API_BASE_URL="$api_url" \
  --dart-define=TLS_SECURITY_PROFILE=developer \
  --dart-define=WRFCOIN_CHAIN_ID="${WRFCOIN_CHAIN_ID}" \
  --dart-define=WRFCOIN_NETWORK_ID="${WRFCOIN_NETWORK_ID:-testnet}" \
  ${auth_define[@]+"${auth_define[@]}"}

apk=build/app/outputs/flutter-apk/app-profile.apk
[[ -s "$apk" ]] || fail "flutter reported success but $apk is missing"

# Exactly one signer, and it must be the Android Debug cert. Nothing is
# reported as built until this passes.
certs="$("$apksigner" verify --print-certs "$apk" 2>/dev/null)" || fail "apksigner verify failed for $apk"
signer_dns="$(grep -E '^Signer #[0-9]+ certificate DN: ' <<<"$certs" || true)"
[[ "$(grep -c . <<<"$signer_dns")" == 1 ]] || fail "expected exactly one APK signer, got: ${signer_dns:-none}"
[[ "$signer_dns" =~ certificate\ DN:\ (.*,\ )?CN=Android\ Debug(,.*)?$ ]] ||
  fail "APK is not debug-signed ($signer_dns); refusing to label it a sideload build"

echo "APK=$repo_root/$apk"
echo "SIZE_BYTES=$(wc -c <"$apk" | tr -d ' ')"
echo "SHA256=$(sha256sum "$apk" | cut -d' ' -f1)"
echo "API_BASE_URL=$api_url"
echo "WALLET_AUTH_ORIGIN=${auth_origin:-<derived from API_BASE_URL>}"
echo "$signer_dns"
echo "PROFILE_APK_OK"
