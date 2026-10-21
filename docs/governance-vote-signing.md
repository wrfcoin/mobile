# Mobile governance vote signing

This build targets the owner-selected chain-777 v1 vote protocol, implemented by
backend PR #1337. The backend operator must select
`WRFCOIN_GOVERNANCE_SIGNING_VERSION=1`. The mobile Dart define of the same name
also defaults to 1. Other mobile versions fail before key access or a vote POST;
this build does not implement v2 or negotiate a version through an API.

The backend currently exposes no signing-version discovery field. Changing the
chain/backend protocol requires a corresponding reviewed mobile release. Do not
interpret a backend vote rejection as permission to try alternate preimages.

For and Against sign the raw UTF-8 bytes
`governance-vote-v1|<proposal_id>|approve` and
`governance-vote-v1|<proposal_id>|reject`. V1 has no length framing or chain/network
binding. Abstain is absent because the backend/core4 vote contract is binary.
The proposal, choice, and preimage are built locally. Only the optional reason
is unsigned, matching the backend contract.

The confirmation dialog precedes one biometric-gated wallet-key access. The
signer refuses background execution, legacy wallets, and a key whose derived
address differs from the stored voting wallet. A different login-wallet address
also refuses signing. The API's existing session policy must report signed in;
voting never starts a login loop. The backend verifies that the signature's
public key derives to the authenticated JWT subject. The phone sends only
`voteType`, `signer_public_key`, `signature`, and optional `reason`.

The collect key is never opened. Synthetic Node-crypto signature fixtures and
production-provider/screen tests cover both choices and cancellation. Local
Flutter tests do not prove physical-device biometric behavior or live voting.
