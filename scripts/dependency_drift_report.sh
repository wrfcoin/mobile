#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="$repo_root/artifacts"
report_path="$artifact_dir/dependency-drift.txt"

mkdir -p "$artifact_dir"

{
  echo "WRFCoin Mobile dependency drift snapshot"
  echo "Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo
  flutter pub outdated
} >"$report_path"
