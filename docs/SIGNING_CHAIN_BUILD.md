# Required signing chain for release and profile builds

Set `--dart-define=WRFCOIN_CHAIN_ID=<confirmed-chain-id>` on every release or profile
build, including direct Flutter builds. Unset or empty values fail constant
evaluation; there is no release or profile fallback. Fastlane requires `WRFCOIN_CHAIN_ID`
and checks that it is a positive JavaScript-safe integer. The network define
still defaults to `testnet`. Confirm both values against the selected deployment.
Debug builds retain their development default.

Run `bash scripts/test-release-chain-define.sh` to compile the real signing
domain: unset and empty release/profile values must fail; explicit test chain values
must survive compilation; the debug default must remain unchanged. The CI
analyze-test job runs these controls. No keystore or node is needed.

The profile helper also requires `WRFCOIN_CHAIN_ID` and passes it unchanged.
For example, set `WRFCOIN_CHAIN_ID=<confirmed-chain-id>` before running
`scripts/build_profile_apk.sh <https-api-url>`. Its stub-only control is
`bash scripts/test_build_profile_apk_gate.sh`; no APK or network access is needed.
