# Fixtures

`station-owner-contract.json` is copied byte for byte from the backend
contract fixture:

- source: `wrfcoin/backend` PR #102 head `9beee4e` (adds
  `features.stationSubmitterKey`, false while the node omits it), path
  `__tests__/fixtures/station-owner-contract.json`. Previously `main` at
  `dec7b920` (backend#1459, sha256 `0b6cb2b4f9e60a77e56aa10b33ecbd6f5f2148dad65148913597705a593ba633`).
- sha256: `4f73964b49dfd0891736d3338ee2e826f5c8abd5d6defa62ec9b275644029315`
  (pinned in `station_owner_contract_test.dart`)

It is generated from the real relay routes. Do not edit it here: regenerate it
in the backend and copy it again.
