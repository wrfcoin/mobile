#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$root/scripts/assert-release-terminal-gate.sh"

run_gate() {
  PREFLIGHT_RESULT="$1" IOS_RESULT="$2" ANDROID_RESULT="$3" RELEASE_IOS="$4" RELEASE_ANDROID="$5" "$gate"
}

run_gate success success success true true
run_gate success success skipped true false
run_gate success skipped success false true

if run_gate success skipped success true true; then
  echo "selected iOS release incorrectly accepted a skipped job" >&2
  exit 1
fi

if run_gate failure skipped skipped false false; then
  echo "failed preflight incorrectly accepted" >&2
  exit 1
fi

if run_gate success success skipped false false; then
  echo "unselected iOS incorrectly accepted a job that ran" >&2
  exit 1
fi

if run_gate success skipped skipped "" false; then
  echo "empty platform selection incorrectly accepted" >&2
  exit 1
fi

echo "mobile release terminal-gate controls passed"
