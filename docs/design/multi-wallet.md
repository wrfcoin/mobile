# Multi-wallet support: design note (DRAFT, for owner ratification)

Refs wrfcoin/mobile-archive#434. No code in this PR. The overnight contract says to stop after a design note when a
safe migration cannot yet be proven with tests; this is that note.

## Why this stopped at a design note

`KeyManager` (`lib/services/crypto/key_manager.dart`) is a single-slot store: `wrf_mnemonic`, `wrf_private_key`,
`wrf_address`, `wrf_key_scheme`, `wrf_login_private_key`, `wrf_login_address`, plus the auth session
(`wrf_jwt`, `wrf_refresh_token`, `wrf_jwt_expires_at`, `wrf_auth_wallet_scheme`). `WalletSecureStorage` adds
`wrf_address`, `wrf_backup_confirmed`, `wrf_is_social`, `wrf_address_book`. `keyManagerProvider` is read by 19 files,
including the background `sync_worker` isolate. Changing which slot "the wallet" means touches signing, login, the
station id (`deriveMobileStationId(address)`) and the collect key (`collect_key_owner`). A half-built version could
strand a wallet's phrase or sign with the wrong key, so it is not worth shipping unproven overnight.

## Decisions needed from the owner

1. **Which wallet does the station earn to?** Today the station id is derived from the wallet address and the collect
   key is registered to that owner. Proposal: the station stays bound to the wallet it was registered with (the
   "station wallet"), shown in Settings, and switching the active wallet never re-registers or moves attribution.
   Changing the station wallet is a separate, explicit action (the existing transfer flow).
2. Whether removing a wallet that owns the station is blocked, or allowed after the transfer flow. Proposal: blocked.

## Proposed storage layout

New namespaced slots in the same secure storage, one set per wallet id (`w1`, `w2`, ...; the id is random, not the
address, so nothing sensitive is in a key name):

`wrf_w:<id>:mnemonic | private_key | address | key_scheme | login_private_key | login_address | backup_confirmed | is_social`

plus a non-secret index `wrf_wallets_index` (JSON list of `{id, label, address, createdAt}`) and `wrf_wallets_active`.
The index holds addresses, never key material. The auth session stays a single slot, tagged with the wallet id it was
minted for; switching wallets clears it and the next login mints a session for the new wallet (the existing
`clearAuthSession` path).

`KeyManager` keeps its public API. Behind the flag it resolves the active wallet id and reads the namespaced slots;
with the flag off it reads the legacy slots exactly as today, so default behaviour is unchanged.

## Migration (lossless, never destructive)

Run once, on first launch with the flag on, only when the index is absent and the legacy `wrf_address` exists:

1. Read the legacy slots. If the mnemonic and private key do not both read back, abort: write nothing, change nothing.
2. Write wallet `w1` slots (copy, do not move).
3. Read every `w1` slot back and compare with the legacy values. Any mismatch: delete the partial `w1` slots,
   abort, keep legacy.
4. Only then write the index and the active pointer (the commit point).
5. Leave the legacy slots in place for one release. A crash at any step before 4 leaves the install exactly as it was;
   after 4 both copies exist. Legacy slots are removed by a later, separate change after an owner-approved release.

The key-name prefix and values are never logged; tests assert that no log line contains key material.

## Flag and UI

`VITE`-style flag `enableMultiWallet`, default off, in `feature_flags.dart`. With it on: a switcher in the wallet
header, per-wallet labels, an "Add wallet" entry (create or import, import no longer replaces), removal behind a
confirmation plus a backup reminder, and Send shows the sending wallet. Emergency Wipe keeps wiping everything.

## Required tests before any code merges

- Migration from a single-wallet install: old slots still readable after migration; killed at each step 1-4 leaves
  a usable wallet; mismatch aborts without data loss; second run is a no-op.
- Switching: active wallet changes balance, history and Send; auth session cleared on switch.
- Send signs only with the selected wallet's key (assert the signer's public key matches the selected address).
- Removal: confirmation required; station wallet cannot be removed; other wallets' slots untouched.
- Station/collect key: switching does not touch `collect_key_*` or re-register; `sync_worker` still uses the station
  wallet.
- Flag off: byte-identical behaviour to main (existing wallet tests unchanged).
- No key material in logs.

## Suggested sequence

PR 1 `WalletVault` + migration + tests, no UI, flag off. PR 2 switcher UI + Send header. PR 3 add/remove flows. Each
is separately reviewable and reversible.
