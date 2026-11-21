# Fixtures

`station-owner-contract.json` is copied byte for byte from the backend
contract fixture:

- source: `wrfcoin/backend` `main` at `f5d6658` (backend#103, merged: adds
  `"submitterKey": null` to each ownership response), path
  `__tests__/fixtures/station-owner-contract.json`
- sha256: `2060a6f87c99a9a605a03f1ec4ed15b9b49367ff4b4cd98025a676aea6ae4aba`
  (pinned in `station_owner_contract_test.dart`)
- history: backend#102 head `9beee4e` (sha256 `4f73964b49dfd0891736d3338ee2e826f5c8abd5d6defa62ec9b275644029315`,
  added `features.stationSubmitterKey`); before that `main` at `dec7b920`
  (backend#1459, sha256 `0b6cb2b4f9e60a77e56aa10b33ecbd6f5f2148dad65148913597705a593ba633`).

It is generated from the real relay routes. Do not edit it here: regenerate it
in the backend and copy it again.
