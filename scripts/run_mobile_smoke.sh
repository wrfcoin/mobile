#!/usr/bin/env bash
# CI smoke is always synthetic. Live operator checks remain a separate action.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export TESTNET_SMOKE_BASE_URL=''
export TESTNET_SMOKE_WALLET_ADDRESS=''
export TESTNET_SMOKE_WEATHER_SUBMIT_PATH=''
export TESTNET_SMOKE_NODE_STATUS_PATH=''
unset WRFCOIN_LIVE_SEND_CHECK WRFCOIN_E2E_BASE_URL
exec flutter test --no-pub --concurrency=2 \
  test/integration/testnet_smoke_probe_test.dart \
  test/integration/testnet_smoke_widget_test.dart \
  test/integration/testnet_smoke_wallet_send_test.dart
