#!/usr/bin/env bash
# Owner-run live testnet send check (GO step 5). NOT run by CI; never run it from an agent.
#
#   bash scripts/live_testnet_send_check.sh check   # faucet precondition + wallet/login/nonce read, no transaction
#   bash scripts/live_testnet_send_check.sh claim   # ONE faucet claim (asks you one math question)
#   bash scripts/live_testnet_send_check.sh send    # ONE 1-WRF send, then a bounded inclusion poll
#
# Order: check -> claim -> wait until `check` prints FUNDED=yes -> send.
# Every step first reads the FAUCET account at the node and STOPS with
# "faucet not funded yet: run after E0f/H_F" if it is absent or has no
# spendable balance, BEFORE any claim or send. (After the genesis cut the faucet
# account only exists from H_F, activated by the E0f block.)
#
# Required environment (secrets by environment only, never on the command line):
#   WRFCOIN_LIVE_NODE_URL        core4 launch_api you can reach, e.g. http://127.0.0.1:8556
#   WRFCOIN_LIVE_READER_TOKEN    core4 READER token (reads addresses; cannot submit)
#   WRFCOIN_LIVE_FAUCET_ADDRESS  the faucet's chain address (public)
# Optional:
#   WRFCOIN_LIVE_BASE_URL        backend API base (default: the tailnet :5000 /api)
#   WRFCOIN_LIVE_AUTH_ORIGIN     the backend's WRFCOIN_WALLET_AUTH_ORIGIN
#   WRFCOIN_LIVE_PUBLIC_URL      public edge for the faucet claim (default: the tailnet edge on :9444)
#   WRFCOIN_LIVE_MNEMONIC_FILE   throwaway mnemonic (mode 600), default ~/.wrfcoin-live-send-check/mnemonic
#   WRFCOIN_LIVE_AMOUNT          display WRF to send (default 1)
#   WRFCOIN_LIVE_RECIPIENT       0x chain address to send TO; REQUIRED for `send`
#   WRFCOIN_LIVE_SELF_TEST_RECIPIENT=1  explicit opt-in to a random throwaway recipient instead
#   WRFCOIN_LIVE_FEE_BASE_UNITS  fee reserve the sender must hold above the amount (default 1000000 = 0.01 WRF)
# `send` STOPs if the sender's spendable balance is below amount + fee reserve.
# Base URL: the default is the tailnet :5000 /api. For the owner run prefer the edge,
# WRFCOIN_LIVE_BASE_URL=https://wrfcoin-testnet.taila1c049.ts.net:9444/api (see docs/testing/live-send-smoke-owner.md).
#
# What it does and does not do: signs with chain 777 / testnet (pinned in the Dart
# test, not a build-time override); prints only addresses, nonces, tx ids and
# balances, never the mnemonic, a key, a JWT or a token; makes one faucet claim,
# one send (never retried) and at most 30 nonce reads after it; never mines and
# holds no operator token.
#
# OWNER NOTE, if you send with the core4 CLI instead of this script:
#   * `wrfcoin wallet send` signs with WRFCOIN_CHAIN_ID / WRFCOIN_NETWORK_ID from ITS OWN
#     environment and otherwise with wrfcoin-main / mainnet. Run it with
#       WRFCOIN_CHAIN_ID=777 WRFCOIN_NETWORK_ID=testnet
#     or core4 answers 400 AUTHORIZATION_INVALID (the preimage folds the chain domain in).
#   * The CLI's bearer is WRFCOIN_OPERATOR_TOKEN, then WRFCOIN_READER_TOKEN. A Reader-only
#     token can read but cannot submit (core4 needs the Contributor role), so the send is refused.
#   * `--amount` is display WRF (a float); the transfer signs base units (1 WRF = 100000000).
set -euo pipefail
STEP=${1:-}
cd "$(dirname "$0")/.."

export WRFCOIN_LIVE_SEND_CHECK=1
export WRFCOIN_LIVE_BASE_URL=${WRFCOIN_LIVE_BASE_URL:-http://wrfcoin-testnet.taila1c049.ts.net:5000/api}
export WRFCOIN_LIVE_AUTH_ORIGIN=${WRFCOIN_LIVE_AUTH_ORIGIN:-https://wrfcoin-testnet.taila1c049.ts.net}
export WRFCOIN_LIVE_MNEMONIC_FILE=${WRFCOIN_LIVE_MNEMONIC_FILE:-$HOME/.wrfcoin-live-send-check/mnemonic}
export WRFCOIN_LIVE_AMOUNT=${WRFCOIN_LIVE_AMOUNT:-1}
# The edge serves invitees on :9444; the bare host has no listener there, so the default carries the port.
PUBLIC=${WRFCOIN_LIVE_PUBLIC_URL:-https://wrfcoin-testnet.taila1c049.ts.net:9444}
TEST=test/integration/live_testnet_send_check_test.dart

usage() { echo "usage: $0 check|claim|send" >&2; exit 2; }
case "$STEP" in check|claim|send) ;; *) usage ;; esac

if [[ "$STEP" == "send" && -z "${WRFCOIN_LIVE_RECIPIENT:-}" && "${WRFCOIN_LIVE_SELF_TEST_RECIPIENT:-}" != "1" ]]; then
  echo "STOP WRFCOIN_LIVE_RECIPIENT must be set for send (or WRFCOIN_LIVE_SELF_TEST_RECIPIENT=1 for a random throwaway recipient)" >&2
  exit 1
fi

for name in WRFCOIN_LIVE_NODE_URL WRFCOIN_LIVE_READER_TOKEN WRFCOIN_LIVE_FAUCET_ADDRESS; do
  if [[ -z "${!name:-}" ]]; then
    echo "STOP $name must be set in the environment (see the header of this script)" >&2
    exit 1
  fi
done

OUT=$(mktemp)
MNEMONIC_TEXT=""
# The wallet canonicalizes a mnemonic as trim + lowercase + collapse whitespace
# (WalletSetupService.importFromMnemonic); the guard uses the same form. It is refreshed after
# every Dart step, because the first run CREATES the file, and before anything is printed.
load_mnemonic() {
  MNEMONIC_TEXT=""
  [[ -r "$WRFCOIN_LIVE_MNEMONIC_FILE" ]] || return 0
  MNEMONIC_TEXT=$(tr '[:upper:]' '[:lower:]' < "$WRFCOIN_LIVE_MNEMONIC_FILE" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
}
load_mnemonic
trap 'rm -f "$OUT" "$OUT.claim" "$OUT.raw"' EXIT

# Every line this script prints goes through emit(): a line containing the Reader token, the
# mnemonic, or anything shaped like a JWT is replaced by a plain STOP and the run ends. This
# covers the Dart step's output AND the shell's own echo of the faucet responses.
leaks() {
  local l=$1
  [[ -n "${WRFCOIN_LIVE_READER_TOKEN:-}" && "$l" == *"$WRFCOIN_LIVE_READER_TOKEN"* ]] && return 0
  # The candidate is normalized exactly like the mnemonic (lowercase, every whitespace run -> one
  # space, trimmed) so doubled spaces, tabs or newlines between the words cannot hide it.
  local norm
  norm=$(printf '%s' "$l" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')
  [[ -n "$MNEMONIC_TEXT" && "$norm" == *"$MNEMONIC_TEXT"* ]] && return 0
  [[ "$l" =~ eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,} ]] && return 0
  return 1
}
emit() {
  if leaks "$1"; then
    echo "STOP a line of output contained a secret and was suppressed" >&2
    exit 1
  fi
  printf '%s\n' "$1"
}

# Runs one Dart step. Only its "LIVE ..." lines are shown; the test runner's other
# output is dropped so nothing but public data reaches the terminal.
run_step() {
  local rc=0
  echo "== running flutter step: $1 (compiles first; silent for up to ~1 minute, do NOT press Ctrl-C)"
  WRFCOIN_LIVE_STEP=$1 flutter test --no-pub "$TEST" > "$OUT.raw" 2>&1 || rc=$?
  load_mnemonic # the step may have created or normalized the file; learn it BEFORE printing
  sed -n 's/^LIVE //p' "$OUT.raw" > "$OUT"
  rm -f "$OUT.raw"
  local line
  while IFS= read -r line; do emit "$line"; done < "$OUT"
  if [[ $rc -ne 0 ]]; then
    grep -q '^STOP ' "$OUT" || echo "check failed (exit $rc); if an ACCEPTED or unknown outcome line is shown above the send may have been admitted: check the wallet nonce before any retry" >&2
    return "$rc"
  fi
}

# Every step: faucet precondition first (the Dart 'check' step STOPs before anything else).
run_step check
FUNDED=$(sed -n 's/^FUNDED=//p' "$OUT" | tail -1)
ADDR=$(sed -n 's/^ADDRESS=//p' "$OUT" | tail -1)

case "$STEP" in
  check)
    ;;
  claim)
    if [[ "$FUNDED" == "yes" ]]; then
      echo "wallet $ADDR is already on chain; not claiming again"
      exit 0
    fi
    [[ "$ADDR" =~ ^0x[0-9a-f]{40}$ ]] || { echo "STOP could not read the wallet address"; exit 1; }
    emit "== ONE faucet claim for $ADDR"
    echo "== requesting faucet challenge from $PUBLIC (20 s limit)"
    CH=$(curl -fsS --max-time 20 -X POST "$PUBLIC/api/onboarding/faucet/challenge" -H 'Content-Type: application/json' -d '{}') || {
      echo "STOP the faucet challenge request failed or timed out; no claim was made. If it timed out, check the tailscale0 MTU (see the owner sheet)" >&2
      exit 1
    }
    # Only validated public fields are ever printed: the id must be a short token and the
    # question a short arithmetic prompt; anything else is a STOP, never echoed.
    ID=$(printf '%s' "$CH" | python3 -c 'import json,re,sys
d=json.load(sys.stdin); v=str(d.get("challengeId",""))
print(v if re.fullmatch(r"[A-Za-z0-9_-]{1,64}",v) else "")') || ID=""
    Q=$(printf '%s' "$CH" | python3 -c 'import json,re,sys
d=json.load(sys.stdin); v=str(d.get("question",""))
print(v if re.fullmatch(r"[0-9A-Za-z +*/=?.,()x-]{1,80}",v) and not re.search(r"[A-Za-z0-9]{20}",v) else "")') || Q=""
    if [[ -z "$ID" || -z "$Q" ]]; then
      echo "STOP the faucet challenge was not in the expected shape; nothing was printed from it and no claim was made"
      exit 1
    fi
    # Every response-derived value is data: check ALL of them for known secrets before any is
    # printed or placed in an argument list / request payload.
    load_mnemonic
    if leaks "$Q" || leaks "$ID"; then
      echo "STOP the faucet challenge contained a secret; nothing was printed from it and no claim was made" >&2
      exit 1
    fi
    read -r -p "$Q " ANSWER
    BODY=$(python3 -c 'import json,sys;print(json.dumps({"walletAddress":sys.argv[1],"challengeId":sys.argv[2],"answer":sys.argv[3]}))' "$ADDR" "$ID" "$ANSWER")
    echo "== submitting the ONE faucet claim (30 s limit)"
    CODE=$(curl -sS --max-time 30 -o "$OUT.claim" -w '%{http_code}' -X POST "$PUBLIC/api/onboarding/faucet/claim" -H 'Content-Type: application/json' -d "$BODY") || {
      echo "STOP the faucet claim request failed or timed out: the outcome is UNKNOWN (the claim may have been accepted). Run '$0 check' before any retry; do not claim again until it shows FUNDED=no" >&2
      exit 1
    }
    # Print only the status code and whitelisted, validated public fields of the response.
    SUMMARY=$(python3 -c 'import json,re,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    d={}
out=[]
if isinstance(d,dict):
    for k,pat in (("status",r"[A-Za-z_ -]{1,40}"),("txHash",r"(0x)?[0-9a-fA-F]{8,128}"),("tx_hash",r"(0x)?[0-9a-fA-F]{8,128}"),("amount",r"[0-9]{1,20}")):
        v=d.get(k)
        if v is not None and re.fullmatch(pat,str(v)):
            out.append("%s=%s"%(k,v))
print(" ".join(out))' "$OUT.claim" 2>/dev/null) || SUMMARY=""
    emit "faucet claim HTTP $CODE ${SUMMARY:+($SUMMARY)}"
    [[ "$CODE" == 2* ]] || { echo "faucet claim failed; not retrying"; exit 1; }
    echo "Claim submitted once. Run '$0 check' until it prints FUNDED=yes, then '$0 send'."
    ;;
  send)
    if [[ "$FUNDED" != "yes" ]]; then
      echo "STOP wallet not funded on chain yet: run claim, wait until check prints FUNDED=yes, then send"
      exit 1
    fi
    run_step send
    ;;
esac
