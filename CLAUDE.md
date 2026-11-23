# Last Word

A tamper-proof will registry, built for the **HASH-IT-OUT** 2-day blockchain hackathon
(theme: **Verifiable Records**). Solidity, deployed to **Base Sepolia**.

## Product

- Notaries file a **SHA-256 fingerprint** of a will PDF. The PDF content itself never goes on-chain.
- An amendment is a **new version**. Nothing is ever edited or deleted: history is append-only.
- Once a **death is recorded** for a will, no new versions can be filed. This blocks backdated or
  forged wills that show up after the testator has died.
- **Anyone can verify** a document against the registry with no wallet (read-only calls).

## Roles

| Role          | Who                               | Can do                                                  |
|---------------|-----------------------------------|---------------------------------------------------------|
| Admin         | The registry (contract deployer)  | Add/remove notaries, record deaths                      |
| Notary        | Address approved by the admin     | File wills and amendments                               |
| Public reader | Anyone, no wallet                 | Read versions, check whether a hash matches a version   |

## Data rules

- **All data is fake.** Will IDs look like `"T-001"`, `"T-002"`. Never use real names or personal data
  anywhere: contract, tests, scripts, frontend, demo.
- On-chain we store only hashes, timestamps, and notary addresses.

## Repo layout

```
contracts/LastWord.sol   # the registry contract (Solidity ^0.8.24, no external deps)
test/LastWord.t.sol      # Foundry tests (forge-std)
foundry.toml             # src = "contracts"
```

## Contract design (contracts/LastWord.sol)

- `admin` is set in the constructor (the deployer).
- `addNotary(address)` / `removeNotary(address)`: admin only.
- `fileWill(string willId, bytes32 docHash)`: approved notaries only. Reverts if the testator is deceased,
  if the hash is empty, or if `docHash` equals the latest version's hash.
- Versions are stored per `willId` as an array of `{bytes32 docHash, uint64 filedAt, address notary}`.
- `recordDeath(string willId, bytes32 certHash)`: admin only, once per will, and the will must already
  have at least one version.
- Views: `getVersions`, `getLatest`, `versionCount`, `deceasedAt`, `isNotary`,
  `findVersion(willId, docHash) -> (bool found, uint index, bool isLatest)`.
- Custom errors: `NotAdmin`, `NotANotary`, `TestatorDeceased(uint64 at)`, `AlreadyDeceased`,
  `NoWillFiled`, `EmptyHash`, `DuplicateVersion`.
- Events: `NotaryAdded`, `NotaryRemoved`, `WillFiled(willId, version, docHash, notary)`,
  `DeathRecorded(willId, certHash)`.

## Conventions

- Keep the contract **small and readable**. No upgradeability, no proxies, no external libraries.
- NatSpec on every function.
- Custom errors, not revert strings.
- Every revert path has a test.
- Test gotcha: don't declare test hashes as `bytes32 constant X = sha256(...)`. `sha256` is a precompile
  call evaluated at each use, so it consumes `vm.prank` before the real call. Use `immutable` instead.

## Commands

```sh
forge build
forge test -vv
```
