#!/usr/bin/env bash
# Reuse packages first. Only the existing hosted bootstrap may fetch misses.
# A future self-hosted runner must have a warm SDK/pub cache before admission.
set -euo pipefail
if flutter pub get --offline --enforce-lockfile; then
  exit 0
fi
if [[ "${RUNNER_ENVIRONMENT:-}" != 'github-hosted' ]]; then
  echo 'PUB_CACHE_REQUIRED: offline locked dependencies unavailable; no network fallback' >&2
  exit 1
fi
flutter pub get --enforce-lockfile
