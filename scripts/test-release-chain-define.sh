#!/usr/bin/env bash
# Compile the real, dependency-free signing domain; no Android SDK or keys.
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d)
trap 'result=$?; if [[ $result != 0 ]]; then cat "$task_dir/build.log"; fi; rm -f "$task_dir/probe.dart" "$task_dir/probe.dill" "$task_dir/build.log"; rmdir "$task_dir"' EXIT
printf "import '%s/lib/services/crypto/transfer_signing_domain.dart';\nvoid main() { print(TransferSigningDomain.configured.chainId); }\n" "$PWD" > "$task_dir/probe.dart"
for mode in release profile; do
  mode_args=(-Ddart.vm.product=true -Ddart.vm.profile=false)
  if [[ $mode == profile ]]; then
    mode_args=(-Ddart.vm.product=false -Ddart.vm.profile=true)
  fi
  for chain in unset blank; do
    args=("${mode_args[@]}")
    if [[ $chain == blank ]]; then args+=(-DWRFCOIN_CHAIN_ID=); fi
    if dart compile kernel "${args[@]}" "$task_dir/probe.dart" -o "$task_dir/probe.dill" > "$task_dir/build.log" 2>&1; then
      echo "FAIL: $mode compiled with $chain chain"; exit 1
    fi
    grep -q 'WRFCOIN_CHAIN_ID is required' "$task_dir/build.log"
  done
  for chain in 777 888; do
    dart compile kernel "${mode_args[@]}" -DWRFCOIN_CHAIN_ID="$chain" "$task_dir/probe.dart" -o "$task_dir/probe.dill" > "$task_dir/build.log" 2>&1
    [[ $(dart "$task_dir/probe.dill") == "$chain" ]]
  done
done
dart compile kernel -Ddart.vm.product=false -Ddart.vm.profile=false "$task_dir/probe.dart" -o "$task_dir/probe.dill" > "$task_dir/build.log" 2>&1
[[ $(dart "$task_dir/probe.dill") == 777 ]]
echo 'PASS: release/profile unset/blank rejected; explicit 777/888 preserved in both modes; debug default 777'
