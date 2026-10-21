#!/usr/bin/env bash
# Offline checks of scripts/live_testnet_send_check.sh: usage errors, missing
# environment, and that no secret is ever placed on a command line. Makes no
# network call and never starts flutter.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
S=scripts/live_testnet_send_check.sh
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

out=$(bash "$S" 2>&1); rc=$?; [[ $rc -eq 2 && "$out" == *usage* ]] && ok "no step -> usage, exit 2" || bad "no step -> usage (rc=$rc)"
out=$(bash "$S" bogus 2>&1); rc=$?; [[ $rc -eq 2 ]] && ok "unknown step -> exit 2" || bad "unknown step (rc=$rc)"
for missing in WRFCOIN_LIVE_NODE_URL WRFCOIN_LIVE_READER_TOKEN WRFCOIN_LIVE_FAUCET_ADDRESS; do
  env -u WRFCOIN_LIVE_NODE_URL -u WRFCOIN_LIVE_READER_TOKEN -u WRFCOIN_LIVE_FAUCET_ADDRESS \
    "WRFCOIN_LIVE_NODE_URL=http://127.0.0.1:1" "WRFCOIN_LIVE_READER_TOKEN=x" "WRFCOIN_LIVE_FAUCET_ADDRESS=0x$(printf 'a%.0s' {1..40})" \
    env -u "$missing" bash "$S" check > /tmp/live_send_check_test.out 2>&1; rc=$?
  [[ $rc -eq 1 ]] && grep -q "STOP $missing must be set" /tmp/live_send_check_test.out && ok "missing $missing -> STOP" || bad "missing $missing (rc=$rc)"
done
rm -f /tmp/live_send_check_test.out
# send without a recipient (and without the explicit self-test opt-in) STOPs before anything runs.
out=$(env -u WRFCOIN_LIVE_RECIPIENT -u WRFCOIN_LIVE_SELF_TEST_RECIPIENT bash "$S" send 2>&1); rc=$?
[[ $rc -eq 1 && "$out" == *"STOP WRFCOIN_LIVE_RECIPIENT must be set"* ]] && ok "send without recipient -> STOP" || bad "send without recipient (rc=$rc)"
# The reader token must never appear on a command line in the script.
if grep -nE 'curl[^#]*READER_TOKEN|flutter[^#]*READER_TOKEN|--header[^#]*READER|-H[^#]*READER_TOKEN' "$S"; then bad "reader token on a command line"; else ok "reader token only via environment"; fi
# The live step must be guarded and CI-inert.
grep -q 'WRFCOIN_LIVE_SEND_CHECK' test/integration/live_testnet_send_check_test.dart && ok "live test guarded by WRFCOIN_LIVE_SEND_CHECK" || bad "live test guard"
if grep -rn 'live_testnet_send_check' .github 2>/dev/null; then bad "referenced from CI"; else ok "not referenced from CI"; fi

# --- stubbed claim orchestration: no network, no flutter. A canary in every response must never print.
STUB=$(mktemp -d); trap 'rm -rf "$STUB"' EXIT
CANARY="CANARYSECRETVALUE0123456789"
JWTLIKE="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIweDEifQ.sig12345"
cat > "$STUB/flutter" <<'EOS'
#!/usr/bin/env bash
echo "LIVE ADDRESS=0x$(printf 'a%.0s' {1..40})"
echo "LIVE FUNDED=${STUB_FUNDED:-no}"
EOS
cat > "$STUB/curl" <<'EOS'
#!/usr/bin/env bash
out=""; url=""; args=("$@")
for ((i=0;i<${#args[@]};i++)); do
  [[ "${args[$i]}" == "-o" ]] && out="${args[$((i+1))]}"
  [[ "${args[$i]}" == http* ]] && url="${args[$i]}"
done
echo "$url" >> "$STUB_DIR/urls"; echo "$*" >> "$STUB_DIR/argv"
if [[ "$url" == */challenge ]]; then
  [[ -n "${STUB_CH_RC:-}" ]] && exit "$STUB_CH_RC"
  printf '%s' "$STUB_CHALLENGE"; exit 0
fi
[[ -n "${STUB_CLAIM_RC:-}" ]] && exit "$STUB_CLAIM_RC"
printf '%s' "$STUB_CLAIM" > "$out"; printf '%s' "${STUB_CODE:-200}"
EOS
chmod +x "$STUB/flutter" "$STUB/curl"
run_claim() { # $1 challenge json, $2 claim json, $3 http code
  : > "$STUB/urls"; : > "$STUB/argv"
  PATH="$STUB:$PATH" STUB_DIR="$STUB" STUB_CHALLENGE="$1" STUB_CLAIM="$2" STUB_CODE="${3:-200}" \
    WRFCOIN_LIVE_NODE_URL=http://127.0.0.1:1 WRFCOIN_LIVE_READER_TOKEN="reader-token-canary-777" \
    WRFCOIN_LIVE_FAUCET_ADDRESS="0x$(printf 'a%.0s' {1..40})" WRFCOIN_LIVE_MNEMONIC_FILE="$STUB/none" \
    bash "$S" claim <<< "5" > "$STUB/out" 2>&1
}
GOODCH='{"challengeId":"c-123","question":"What is 2 + 3?"}'
run_claim "$GOODCH" '{"status":"queued","txHash":"0xabcdef0123456789","note":"'"$CANARY"'","echo":"'"$JWTLIKE"'","token":"reader-token-canary-777"}'; rc=$?
[[ $rc -eq 0 && $(grep -c 'faucet claim HTTP 200' "$STUB/out") -eq 1 ]] && ok "claim prints the status code and validated fields" || bad "claim happy path (rc=$rc)"
! grep -q "$CANARY\|eyJ\|reader-token-canary-777" "$STUB/out" && ok "claim response body is never echoed" || bad "claim response canary leaked"
run_claim "$GOODCH" '{"error":"'"$CANARY"'"}' 500; rc=$?
[[ $rc -eq 1 ]] && ! grep -q "$CANARY" "$STUB/out" && ok "failed claim: code only, no body, no retry" || bad "failed claim leaked or retried (rc=$rc)"
[[ $(grep -c '/claim' "$STUB/urls") -eq 1 ]] && ok "exactly one claim POST" || bad "claim POST count"
run_claim '{"challengeId":"c-1","question":"What is 2 + 3? '"$CANARY"'"}' '{}'; rc=$?
[[ $rc -eq 1 ]] && ! grep -q "$CANARY" "$STUB/out" && ! grep -q '/claim' "$STUB/urls" && ok "hostile challenge question: STOP, not printed, no claim" || bad "hostile challenge (rc=$rc)"
run_claim '{"challengeId":"c 1 ;x","question":"What is 2 + 3?"}' '{}'; rc=$?
[[ $rc -eq 1 ]] && ! grep -q '/claim' "$STUB/urls" && ok "malformed challenge id: STOP, no claim" || bad "malformed id (rc=$rc)"
# shell echo of a secret in the Dart step's own output is also suppressed
cat > "$STUB/flutter" <<'EOS'
#!/usr/bin/env bash
echo "LIVE ADDRESS=0x$(printf 'a%.0s' {1..40})"
echo "LIVE HTTP GET /x -> 500 reader-token-canary-777"
EOS
run_claim "$GOODCH" '{}'; rc=$?
[[ $rc -eq 1 ]] && ! grep -q "reader-token-canary-777" "$STUB/out" && ok "step output containing the token is suppressed" || bad "step output leaked (rc=$rc)"
# --- round 3: mnemonic created/normalized by the step, and a secret-bearing challenge id
PHRASE="legal winner thank year wave sausage worth useful legal winner thank yellow"
cat > "$STUB/flutter" <<'EOS'
#!/usr/bin/env bash
echo "LIVE ADDRESS=0x$(printf 'a%.0s' {1..40})"
echo "LIVE FUNDED=no"
if [[ -n "${STUB_CREATE_MNEMONIC:-}" ]]; then printf '%s\n' "$STUB_CREATE_MNEMONIC" > "$WRFCOIN_LIVE_MNEMONIC_FILE"; fi
exit 0
EOS
run_claim2() { # $1 challenge json, $2 claim json ; extra env passes through
  : > "$STUB/urls"; : > "$STUB/argv"
  PATH="$STUB:$PATH" STUB_DIR="$STUB" STUB_CHALLENGE="$1" STUB_CLAIM="$2" \
    WRFCOIN_LIVE_NODE_URL=http://127.0.0.1:1 WRFCOIN_LIVE_READER_TOKEN="reader-token-canary-777" \
    WRFCOIN_LIVE_FAUCET_ADDRESS="0x$(printf 'a%.0s' {1..40})" WRFCOIN_LIVE_MNEMONIC_FILE="$STUB/mnemonic" \
    bash "$S" claim <<< "5" > "$STUB/out" 2>&1
}
rm -f "$STUB/mnemonic"
run_claim2 '{"challengeId":"c-9","question":"What is 2 + 3?"}' '{}'; rc=$?
[[ $rc -eq 0 ]] && grep -q '/claim' "$STUB/urls" && ok "control: the same stubs DO reach the claim with a clean challenge" || bad "control claim (rc=$rc)"
export STUB_CREATE_MNEMONIC="$PHRASE"; run_claim2 '{"challengeId":"c-9","question":"'"$PHRASE"'"}' '{}'; rc=$?
[[ $rc -eq 1 ]] && ! grep -q "thank year wave" "$STUB/out" && ! grep -q '/claim' "$STUB/urls" && ok "mnemonic CREATED by the step: echoed in the question -> STOP, no claim, not printed" || bad "created mnemonic (rc=$rc)"
unset STUB_CREATE_MNEMONIC
printf '  LEGAL  Winner thank year wave   sausage worth useful legal winner thank yellow \n' > "$STUB/mnemonic"
run_claim2 '{"challengeId":"c-9","question":"'"$PHRASE"'"}' '{}'; rc=$?
[[ $rc -eq 1 ]] && ! grep -q "thank year wave" "$STUB/out" && ! grep -q '/claim' "$STUB/urls" && ok "padded/upper-case mnemonic file: canonical phrase in the question -> STOP, no claim" || bad "normalized mnemonic (rc=$rc)"
rm -f "$STUB/mnemonic"
run_claim2 '{"challengeId":"reader-token-canary-777","question":"What is 2 + 3?"}' '{}'; rc=$?
[[ $rc -eq 1 ]] && ! grep -q '/claim' "$STUB/urls" && ! grep -q "reader-token-canary-777" "$STUB/argv" "$STUB/out" && ok "challenge id equal to the Reader token: STOP, never in argv, no claim" || bad "secret challenge id (rc=$rc)"
# round 4: whitespace variations between the words of a known mnemonic must not hide it
printf '%s\n' "$PHRASE" > "$STUB/mnemonic"
for variant in 'doubled space:legal  winner thank year wave sausage worth useful legal winner thank yellow' \
               'tab:legal\twinner thank year wave sausage worth useful legal winner thank yellow' \
               'newline:legal\nwinner thank year wave sausage worth useful legal winner thank yellow' \
               'upper+doubled:LEGAL  WINNER thank year wave sausage worth useful legal winner thank yellow'; do
  label=${variant%%:*}; text=${variant#*:}
  for field in question id; do
    if [[ $field == question ]]; then ch='{"challengeId":"c-9","question":"'"$text"'"}'; else ch='{"challengeId":"'"$text"'","question":"What is 2 + 3?"}'; fi
    run_claim2 "$ch" '{}'; rc=$?
    [[ $rc -eq 1 ]] && ! grep -q '/claim' "$STUB/urls" && ! grep -qi "thank year wave" "$STUB/out" "$STUB/argv" && ok "mnemonic with $label in the challenge $field: STOP, no claim" || bad "mnemonic $label in $field (rc=$rc)"
  done
done
rm -f "$STUB/mnemonic"
# --- owner-run gaps: progress lines, curl time limits, :9444 default, timeout outcomes
run_claim2 "$GOODCH" '{}'; rc=$?
grep -q 'running flutter step: check' "$STUB/out" && grep -q 'requesting faucet challenge' "$STUB/out" && ok "progress lines before flutter and the challenge request" || bad "progress lines"
grep -q -- '--max-time 20' <(grep '/challenge' "$STUB/argv") && ok "challenge curl has --max-time 20" || bad "challenge --max-time"
grep -q -- '--max-time 30' <(grep '/claim' "$STUB/argv") && ok "claim curl has --max-time 30" || bad "claim --max-time"
grep -q ':9444/api/onboarding/faucet/challenge' "$STUB/urls" && ok "default public URL includes :9444" || bad "default public URL lacks :9444"
STUB_CH_RC=28 run_claim2 "$GOODCH" '{}'; rc=$?
[[ $rc -eq 1 ]] && grep -q 'STOP' "$STUB/out" && grep -q 'no claim was made' "$STUB/out" && ! grep -q '/claim' "$STUB/urls" && ok "challenge timeout: STOP, no claim" || bad "challenge timeout (rc=$rc)"
STUB_CLAIM_RC=28 run_claim2 "$GOODCH" '{}'; rc=$?
[[ $rc -eq 1 ]] && grep -q 'UNKNOWN' "$STUB/out" && grep -q "check" "$STUB/out" && grep -qi 'before any retry' "$STUB/out" && [[ $(grep -c '/claim' "$STUB/urls") -eq 1 ]] && ok "claim timeout: outcome UNKNOWN, run check before retry, one POST" || bad "claim timeout (rc=$rc)"
exit $fail
