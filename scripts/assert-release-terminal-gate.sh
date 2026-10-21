#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL-CLOSED: $*" >&2
  exit 1
}

require_result() {
  local job="$1" expected="$2" actual="$3"
  [ "$actual" = "$expected" ] || fail "$job result=$actual, expected $expected"
}

require_result preflight success "${PREFLIGHT_RESULT:-}"

for platform in ios android; do
  selected_var="RELEASE_${platform^^}"
  result_var="${platform^^}_RESULT"
  selected="${!selected_var:-}"
  result="${!result_var:-}"
  case "$selected" in
    true) require_result "${platform}_release" success "$result" ;;
    false) require_result "${platform}_release" skipped "$result" ;;
    *) fail "$selected_var must be true or false, got ${selected:-<empty>}" ;;
  esac
done

echo "mobile release terminal gate passed"
