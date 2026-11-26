<!-- Resumable R2 implementation record (R2-DEV-03; plan §14, O-7): branch and baseline, milestone, completed requirements, files, commands and results with evidence, blockers, pending owner sessions, permissions, the last buildable checkpoint, the quota guard and the next steps. -->
# Lisa R2 — Checkpoint

**Updated:** 2026-11-26T03:15Z by Claude, run `20261124-r2-5462`. **Milestone:** M0 complete; **M1 complete at its boundary** (X1 handed to the owner; **X1's first attempt failed at the Xcode build; attempt 2 requested at `795b4f3`**, §6); **M2 — Replication engine, complete at its boundary** (the clean reconstruction of `815bbbc`; `docs/VERIFICATION-SCENARIOS.md`, "M2 boundary"; `docs/REQUIREMENTS-MATRIX.md`). **M3 in progress:**
- **Done:** M3-0 (frozen fixtures), M3-1 (schema v5 and the Core ledger's intake), M3-2 (full snapshots from Core), M3-3 (receipts verified on a replica), M3-4's first slice (the direct path over loopback HTTP), and M3-D61.
- **Also done:**
  - M3-5a, enrollment and the roster end to end over loopback HTTP (harness v10, 8/8);
  - M3-5b, S-04 and S-05 over R1's real TLS server with the test-only libcurl pinning transport (harness v14, 5/5);
  - M3-5c, credential reset and challenges (harness v15, 10/10);
  - M3-5d's first items, an expired certificate and roster renewal (harness v16, 6/6);
  - M3-4's leftovers: capabilities negotiation with `upgrade_required` (M3-4b, D-63, harness v17, 11/11) and the per-path body limit for `POST /v2/operations` (M3-4c, D-64, harness v18, 12/12);
  - M3-5d's export-key rotation, with an old archive still opening (harness v19, 13/13);
  - M3-5d's signing-key rotation with key history and K2 on a fresh host (D-65, harness v20, 15/15), and device key rotation with historical keys for committed operations (D-66, harness v22, 16/16).

  Each is in §11 and `docs/VERIFICATION-SCENARIOS.md`. M3-5 is done except re-anchoring (with M3-7) and the conditional Design B certificates.
- **M3-6 begun:**
  - M3-6a's legacy children and Core's conversion frame (harness v26);
  - one R1 revision step per R1 call with the projection-revision map (D-68; harnesses v28 and v30);
  - Core's resolution of legacy edits' "observed at projection revision N" (D-69, schema v11; harness v33, 15/15).
  - The replica side (2026-11-26): Core serves the resolved horizon in its signed entries, and replicas fold with it (`53e2a5a`–`89fcb1a`; harness v34, 20/20; regression v19).
  - R1's `POST /v1/tasks` through the legacy converter in R1's router (D-71; `f4879b6`–`12bd3fb`; harness v36, 7/7, against R1's own path; regression v20). It isn't enabled in `LisaHost` yet.
  - R1's `PATCH /v1/tasks/{id}` through the converter (D-72; `ae0c52d`–`6cc8073`; harness v38, 15/15, against R1's own path). It adds two protocol rules: a reopen that names nothing, and an empty notes replacement. R1's in progress and blocked are R1-only states of an open task.

  M3-6a's task routes are done.
- **M3-6b begun (2026-11-26):**
  - the preference operations, the key's entity and its register merge (D-73; `95d3e55`–`fc1c17f`; harness v41, 7/7);
  - preferences at Core and on a replica (`f404e2c`–`44cb3ed`; harness v43, 5/5);
  - step 3a: R1's `PATCH /v1/preferences` through the converter, and Core's refusal of a device's change to an administrative key (D-74; `aa0ec19`–`8313d30`; harness v45, 10/10);
  - step 3b-i: administrative holds, with decision keys and tokens (D-75; `9b09007`–`1621ecb`; harnesses v47 and v48, 12/12).

  Next: step 3b-ii, `resolve` (§11).
- **Paused (the sixth pause, quota):** at about 12:26Z, after the records below (§9). The writer was guard launch `L-fc7f9168cc` (session `38d24e96-7ad7-4d63-ba8d-887352afac4e`), resumed at 11:23Z after the fifth pause with 10% used. The reset was at 2026-11-25T16:20:00Z.
- **Not resumed automatically (environment event, §5):**
  - The guard couldn't confirm the reset, because the usage reader's credentials stopped working at 16:23Z.
  - The VM then stopped at about 17:26Z and booted again at 17:32Z. The guard didn't survive the restart.
  - Nothing was lost.
- **X1, recorded 2026-11-26** (the owner said this was not a resume): **`FAIL` at the first Xcode build of `LisaProof`.** Xcode reported "Failed to produce diagnostic for expression; please submit a bug report" at `Apps/Proof/Nearby/ProofNearbyController.swift:130` (§6). Recorded by session `d53fb9c3-…` under lease `interactive:312`, which didn't consume the pause.
- **Resumed (the seventh resume, manual, 2026-11-26T01:04Z),** after the owner approved resuming:
  - It runs in the interactive session `d53fb9c3-…`, pid 312, which holds the lease `interactive:312` and consumed `P-20261125T122450Z-9de75e`.
  - The guard was restarted as pid 17963.
  - First, X1 attempt 2:
    - the failure reproduced on Linux;
    - the fix (`f03cf24`) and a key-path binding hedge (`0528fc3`–`795b4f3`);
    - the whole `LisaProof` target type-checked on Linux against framework stand-ins (D-70);
    - X1 requested again (§6).
  - Next: M3-6a's replica side (§11).
- **The owner's decisions of 2026-11-25** are in force (§5, §7): regenerable build output may be removed, with an explicit record; the replica may release its ballast to open (D-61, `33b0322`).

The environment and execution decisions in force are in `DEVELOPMENT-ENVIRONMENT-REPORT.md` §13, the dated amendment of 2026-11-24. `CONSTRICTION.md` overrides everything, including this record and `plans/R2.md` revision 13.

## 1. Branch and baseline

| Item | State |
|---|---|
| Branch | `feature/distributive`, the only branch consulted |
| Plan | `plans/R2.md` revision 13: approved content `1a5a07d`, approval recorded `05b856e`, unchanged |
| Frozen R1 | `491c90a`. Its code, tests, fixtures, `Package.swift` and `Package.resolved` equal HEAD's: since `491c90a` only `DEVELOPMENT-ENVIRONMENT-REPORT.md` was added and `plans/R2.md` changed |
| Environment record | `051d9d4`, amended in `9951cbd` (signature-gated recipe) and `c40f5d0` (the owner's decisions, §13) |
| Start instruction | The owner, 2026-11-24: begin M0 in the Docker sandbox and execute the approved plan through M9 |
| Platform | Docker Sandboxes VM `lisa.lab`: Debian 13 (trixie) x86_64, clone-mode Git workspace (commits stay in the sandbox until the owner fetches them), rootful Docker 29.10.0. Swift 6.4.2 primary, 6.4.3 for comparison |
| Run | `20261124-r2-5462`, started 2026-11-24T07:42Z; Claude Code session `4e52d1e9-0d10-448b-8239-b9b21ceda630`; run directory `.tmp/r2/20261124-r2-5462/` (ignored by Git, exists only in this sandbox) |
| Lockfile | `Package.resolved` SHA-256 `f846319595094d9399eccd89f565e571db298f5dab8c46543bcd7d95bc91e776` since `fd94a78` (swift-crypto 5.1.2, `docs/DECISIONS.md` D-53). The M0 baseline and the frozen R1 artifacts use R1's `9608e8e0…a37494`, unchanged by every build |

## 2. Requirements

None is closed yet. M0 owes R2-L01 (first run) and R2-L02 (baseline):

| ID | Status now | Evidence |
|---|---|---|
| R2-L01 Portable debug and release builds without Apple SDKs | First run `PASS` for the R1 package (Claude; Debian 13 sandbox, Swift 6.4.2 and 6.4.3, 0 warnings). Final at M9 | §4 |
| R2-L02 Applicable R1 regression behavior remains correct | Baseline `PASS`: the unmodified R1 suite, 376 tests in 66 suites, in debug and release with both toolchains, before and after swift-crypto 5.1.2; no failure to classify, no requirement replaced yet. Repeated at M3, M5, M8 and M9 | §4 |

## 3. Files

- **Uncommitted tracked changes:** none at this update.
- **Commits in this run:** `9951cbd`, `c40f5d0` (`DEVELOPMENT-ENVIRONMENT-REPORT.md`); `0c037c7` (this file); `ad0338d`, `b079c44` (`docs/VERIFICATION-SCENARIOS.md`); `e0b0302` (`docs/REQUIREMENTS-MATRIX.md`); the swift-crypto span `9e35866` → `fd94a78` with `1a49709` (`docs/SETUP-LINUX.md`), `269a2ca` (`docs/ARCHITECTURE.md`) and `866c98d` (`docs/DECISIONS.md` D-53); the `LisaSyncProtocol` span `8244d48` → `4a8826b`; then this update.
- **Commits since the 09:45Z pause:** the nearby frame header and hello form `c096983`–`c69586c`; D-54 `27769d1`; `Apps/Config` and `Apps/Proof` `bc11c09`–`559f4bb` (69 files, then `Apps/project.yml`); `docs/SYNC-PROTOCOL.md` `3079aa3`; the harness `8e58552`–`d0a9e53` (`LisaVerifyKit`, `LisaVerifyCases`, `LisaVerifyServers`, `lisa-verify`, `Harness/` documents and configuration example, `Apps/OwnerVerification`, test plan X1, the `LisaProof` scheme, each span ending in `Package.swift` or its last file); `docs/SETUP-APPLE.md` §9; `docs/REQUIREMENTS-MATRIX.md` `260a582`; then `docs/VERIFICATION-SCENARIOS.md` and this file.
- **Commits since the M1 boundary:** D-55 `ce68f1a`; the WAL guard `c9fed41` (`LisaSQLite`, four files); `28ef7c8`; `LisaMerge` (eight files, then `Package.swift` `72797e1`); `CausalRelease` `386a738`; `6ccfa10`; `docs/CONFLICTS.md` `5b6e0e7`; `d31a943` (this file at the second pause).
- **Commits since the resume at 20:33Z:** the observed set's canonical form `ef9f546`; `LisaReplicaStore`'s first span `5ddd7d2` → `3ee84a0` (28 files); D-56 `528f236`; `Package.swift` `818fe3c`; `docs/VERIFICATION-SCENARIOS.md` M2-3 `742675f`; `4bb6f35` (this file); the reader monitor and capture path `5d9a9c6` → `0aac9d1` (`LisaSQLite` six files, `LisaReplicaStore` three); M2-4 `3455908`; `40ea1b7` (this file); the item payload schemas `57c50b0` → `75326ea` (LisaSyncProtocol, five files), `TaskMergeState` `f093e69` → `8e0e73b` (LisaMerge, three), the store's payload checks `4e0c1e3`; `docs/SYNC-PROTOCOL.md` `43b5369`; `docs/CONFLICTS.md` `fae2ba7`; M2-5 `446c87e`; `6d9f637` (this file); the effective view and persisted causal release `83791b1` → `09cf01a`; M2-6 `76c54e4`; `6af003f` (this file); `LisaLocalSearch` `8b5cb7e` → `cd37d4f` (with D-57 `703e64f`); M2-7 `358406a`; `fb68439` (this file); resolution groups and the advisory note limit `9c88032` → `3fb9b7f`; `docs/SYNC-PROTOCOL.md` `c606ac5`; M2-8 `9b10d32`; `9bfd698` (this file); the monotonic clock `6279859` → `437ca91` (LisaTime, four files); M2-9 and `4fd1ab5` (this file); change pages and partition cursors `839e52e` → `8afac3b` (LisaSyncProtocol three files, LisaTrust two, LisaReplicaStore six); `docs/SYNC-PROTOCOL.md` §8a `e141742`; M2-10 `1f71f1b`; `e3b41ef` (this file); the staged snapshot installation `23a56b9` → `ab0f695`; `docs/SYNC-PROTOCOL.md` §8b `4678165`; M2-11 `f7e1d75`; `eaba8d5` (this file); the reserve checks on non-capture writes `e06c79f` → `177763a`; M2-12 `18c0517`; `c070e9e` (this file); calendar buckets `e1309be` → `e838a98` (LisaSyncProtocol four files, LisaReplicaStore six); `docs/SYNC-PROTOCOL.md` §8a `a84c29e`; M2-13 `f481535`; `0bbb15f` (this file); repairs by generation `07bd0b9` → `799a16f`; `docs/SYNC-PROTOCOL.md` `209059f`; M2-14 `7b3514f`; `391b042` (this file); the planning zone `38410d9` → `c5b5cb1`; `docs/SYNC-PROTOCOL.md` `a040b78`; M2-15 `eb77d92`; `9b9a74d` (this file); derived records in full snapshots `e563114`; M2-16 `409a083`; `642e955` (this file); the M2-17 record `7cf49b4`; revocations `4290ee5` → `9286c07` (LisaReplicaStore, seven files), `docs/SYNC-PROTOCOL.md` §8c `67e0720`, M2-18 `5c84013`; peer custody `7a5405a` → `79e44f1` (LisaSyncProtocol one file, LisaTrust two, LisaReplicaStore three), `docs/SYNC-PROTOCOL.md` `94358e8`, M2-19 `a19d7dc`; the duplicate rules against canonical state (LisaReplicaStore, five files, ending `cdced83`), `docs/SYNC-PROTOCOL.md` §8 and M2-20; then this file.
- **Commits on 2026-11-26:**
  - the X1 record: `b86d272`, `ee98b23`, `8ba308e`;
  - X1 attempt 2: the fix `f03cf24`, then the key-path bindings `0528fc3` → `795b4f3` (`ProofModel`, then the two views);
  - then D-70, `docs/VERIFICATION-SCENARIOS.md` M1-8b, `Harness/docs/SETUP-APPLE.md`, `docs/REQUIREMENTS-MATRIX.md` and this file.
  - M3-6a's observed horizons on replicas: `53e2a5a` → `89fcb1a` (LisaSyncProtocol one file, LisaCoreLedger three, LisaReplicaStore four), then `docs/SYNC-PROTOCOL.md`, `docs/DECISIONS.md` (D-69), `docs/VERIFICATION-SCENARIOS.md` and this file.
  - M3-6a's converted `POST /v1/tasks`: `f4879b6` → `12bd3fb` (LisaCoreLedger, LisaOwnerData, `Package.swift`, LisaLegacyRequests, LisaAPI four), then D-71, `docs/VERIFICATION-SCENARIOS.md` and this file.
  - M3-6a's converted `PATCH /v1/tasks/{id}`: `ae0c52d` → `6cc8073` (LisaSyncProtocol one file, LisaMerge three, LisaCoreLedger two, LisaLegacyRequests one, LisaAPI two), then D-72, `docs/SYNC-PROTOCOL.md`, `docs/VERIFICATION-SCENARIOS.md` and this file.
  - M3-6b's preference model: `95d3e55` → `fc1c17f` (LisaSyncProtocol, LisaTrust, LisaMerge, one file each), then D-73, `docs/SYNC-PROTOCOL.md`, `docs/VERIFICATION-SCENARIOS.md` and this file.
  - M3-6b's preferences at Core and on a replica: `f404e2c` → `44cb3ed` (LisaMerge one file, LisaCoreLedger five, LisaReplicaStore two), then `docs/VERIFICATION-SCENARIOS.md` and this file.
  - M3-6b's converted `PATCH /v1/preferences` (step 3a): `aa0ec19` → `8313d30` (LisaOwnerData one file, `Package.swift`, LisaCoreLedger three, LisaSyncProtocol one, LisaLegacyRequests two, LisaAPI one), then D-74, `docs/SYNC-PROTOCOL.md`, `docs/REQUIREMENTS-MATRIX.md`, `docs/VERIFICATION-SCENARIOS.md` and this file.
  - M3-6b's administrative holds (step 3b-i): `9b09007` → `e920b58` (LisaTrust, LisaStore, LisaCoreLedger, LisaLegacyRequests and LisaAPI, one file each), then `40ec2d7` → `1621ecb` (`Package.swift`, LisaLegacyRequests one file, LisaAPI one), then D-75, `docs/SYNC-PROTOCOL.md`, `docs/VERIFICATION-SCENARIOS.md` and this file.
- **Temporary files:** only under `.tmp/r2/20261124-r2-5462/`: the M0 scripts and logs (`m0/`), the frozen R1 tree and its builds (`m0/r1-src/`), the usage monitor (`usage/`), the guard and its rehearsals (`guard/`), the recipe tests (`notes/`), the M1 harnesses v1–v5, the proof proposal and its checks, the S-24 runs and the clean-checkout matrix (`m1/`); the owner's X1 report (`owner/`); and X1 attempt 2's repro, stand-ins, module build and type-check runs (`x1/`). None is committed; none is removed or overwritten.

## 4. Commands and results (M0)

| Check | Command | Result | Evidence |
|---|---|---|---|
| R1 suite, Swift 6.4.2 debug | `swift build --scratch-path .build/r2-m0-20261124-r2-5462/swift-6.4.2 -c debug --build-tests`, then `…/out/Products/Debug-linux-x86_64/LisaTests-test-runner --testing-library swift-testing` | Build exit 0 (32.2 s, 0 warnings); **376 tests in 66 suites passed**; runner SHA-256 `9240fefd…69f83` | `m0/suite/6.4.2-debug/` |
| R1 suite, 6.4.2 release | The same with `-c release` | Build exit 0 (112.3 s, 0 warnings); **376/66 passed**; runner `a13a5f4d…4d6d0` | `m0/suite/6.4.2-release/` |
| R1 suite, 6.4.3 debug | The same with the 6.4.3 toolchain first on `PATH` and its own scratch path | Build exit 0 (28.6 s, 0 warnings); **376/66 passed**; runner `a67c3607…47ed9` | `m0/suite/6.4.3-debug/` |
| R1 suite, 6.4.3 release | As above, `-c release` | Build exit 0 (111.0 s, 0 warnings); **376/66 passed**; runner `bb163890…820a` | `m0/suite/6.4.3-release/` |
| Offline demo | `lisa demo --data-dir <run>/demo-data --json` with each of the four builds | Exit 0; 8 steps, **30 of 30 checks** each | `m0/suite/*/demo.json` |
| Frozen R1 sources | `git show --no-textconv 491c90a:<path>`, walking `git show 491c90a:<dir>/` (`m0/reconstruct-r1.py`) | 872 files, each byte-exact against `git rev-parse 491c90a:<path>`; manifest SHA-256 `5e0524fc…b46679` | `m0/r1-src/`, `m0/r1-src.manifest.tsv` |
| Frozen R1 `lisa` | In `m0/r1-src/`: `swift build -c debug`, `swift build -c release` (Swift 6.4.2) | Exit 0 both; debug `220690d1…64f0`, release `34ef4335…9bff` | `m0/frozen/` |
| Frozen-client harness and R1 queue files | A temporary package linking R1's `LisaClient` by path; R1's own `OfflineQueue` writes the queue states | Debug and release build, 0 warnings; **25 queue files** across the §8.14.3 histories, each checked field by field; lockfile kept | `m0/frozen-client/` (`queues/MANIFEST.tsv`) |
| Frozen R1 datasets | The frozen `lisa` and its CLI, live paths only against loopback controlled servers | **3 datasets**: dry-run, pending, suppressed, cancelled, failed and a genuine `outcomeUnknown` delivery; reminders, briefs, plans, preferences, devices and a revocation | `m0/frozen-datasets/` (`*/STATE.md`) |
| Dependency change, swift-crypto 5.1.2 | The M0-1 procedure in fresh scratch paths | **PASS**: 376/66 in debug and release with 6.4.2 and 6.4.3, 0 warnings, demo 30/30 | `deps/regression-swift-crypto-5.1.2/` |
| M1-1 canonical JSON, base64url, budgets | Temporary harness `m1/harness/` (swift-testing, public API) | **PASS**, 16 tests in 5 suites; full debug build 0 warnings; R1 suite 376/66 | `m1/` |
| M1-2 to M1-5: crypto primitives, trust and owner texts, operation envelope, Merkle paging | `m1/harness-v2/` (`swift test --force-resolved-versions --manifest-cache none`) | **PASS**: crypto 6, trust 11, envelope and value budget (v2), Merkle (v2); two superseded v1 harness tests fail as recorded (`NOTES.md`, `NOTES-2.md`); R1 suite 376/66 after each span | `docs/VERIFICATION-SCENARIOS.md` M1-2 to M1-5 |
| M1-7 nearby frame header and hello form | `m1/harness-v3/` | **PASS**, 6 tests (and v3's other 46) | `docs/VERIFICATION-SCENARIOS.md` M1-7 |
| M1-8 `Apps/Proof` | `swiftc -parse` on 69 files; Linux type-check of the 38 portable files against HEAD's modules; the certificate encoder with `openssl` | **PASS** (syntax and portable types; no Apple build claimed) after five fixes found in review | M1-8 |
| M1-9 harness core and S-24 at M1 | `m1/harness-v4/` (13 tests), `m1/harness-v5/` (3), `lisa-verify run --mode fixture` | **PASS**: 9 of 9 fixture cases, 25 logical actions, real SIGKILLs and resumes in new processes | M1-9 |
| M1 boundary, clean checkout of `d0a9e53` | `m1/reconstruct-commit.py`, then `m1/clean-20261124T134046Z/matrix.sh` | **PASS**: debug and release 0 warnings, R1 suite 376/66, fixtures 9/9, lint clean apart from R1's own line | M1 boundary |
| M2-0 SQLite WAL-reset: the library and the single-writer guard (D-55) | Debian's packaging read from deb.debian.org (checksum-verified); `m2/harness-v6/` | The library is treated as unfixed; the guard **PASS**, 4 tests; full build and R1 suite 376/66 after the span | `docs/VERIFICATION-SCENARIOS.md` M2-0 |
| M2-1 `LisaMerge` rule state | `m2/harness-v9/` (v7 and v8 superseded) | **PASS**, 7 tests, every permutation converging | M2-1 |
| M2-2 causal readiness and bounded release | `m2/harness-v10/` | **PASS**, 4 tests: the nested fan-out of 105,001 operations within the 256 bounds | M2-2 |
| M2-3 `LisaReplicaStore`, first span | `m2/harness-v12/` (v11 didn't compile, superseded); `m2/suite-after-replica-span1-20261124T205211Z/` | **PASS**, 9 tests: directory and schema, drafts, the restored copy's new incarnation with no sequence reuse (§8.6.4), the duplicate rules, the atomic change rolled back (index failure, `SQLITE_FULL`), the overlay until the canonical row installs; debug build 0 warnings, R1 suite 376/66 | M2-3 |
| M2-4 the reader monitor and the capture path; **the first container use** | `m2/harness-v13/` (host; the first run failed once, product fixed); `m2/container-20261124T2100Z/` (rootful engine, `swift:6.4.2-trixie` `sha256:9733821c…430097`, 48 MiB tmpfs, no network); `m2/suite-after-storage-span-20261124T210553Z/` | **PASS**: a pinned reader released at its budget with the WAL truncated, a low-space release, the sampler never keeping the replica open; on the tmpfs, a burst filling the disk (ballast lets the first capture through, every failure reported, every save present after restart) and a pinned reader released at the space threshold; debug build 0 warnings, R1 suite 376/66 | M2-4 |
| M2-5 the task family's payload schemas and one task merged | `m2/harness-v15/` (v14 never built), `m2/harness-v17/` (v16's one wrong expectation; v12's fixtures now refused by design); `m2/suite-after-payload-schemas-20261124T211753Z/` | **PASS**: payload forms and refusals; the largest note (53,983 bytes) saved and one byte more refused before it is built; an arriving malformed payload refused; `TaskMergeState` converging over every permutation of four sets (55,000+ orders); debug build 0 warnings, R1 suite 376/66 | M2-5 |
| M2-6 the effective view and persisted causal release | `m2/harness-v19/` (v18 never run); `m2/suite-after-effective-view-20261124T212729Z/` | **PASS**: the view following local saves, drafts and a rejection; a relayed edit waiting for its creation; 700 dependents from two peers released within the 256 bounds, round-robin, resumed after closing mid-drain; a forged cycle rejected; debug build 0 warnings, R1 suite 376/66 | M2-6 |
| M2-7 `LisaLocalSearch` behind `ReplicaIndexing` | `m2/harness-v20/`; `m2/harness-v21/` (v17's pinned table list superseded); `m2/suite-after-local-search-20261124T213244Z/` | **PASS**: search following a local edit and its rejection, notes, deletion, a relayed rename once released and after a restart, and 300 seeded random steps with no mismatch between search and view; debug build 0 warnings, R1 suite 376/66 | M2-7 |
| M2-8 paged resolution groups and the advisory note limit (S-07 M2 replica part) | `m2/harness-v25/` (v22 never built, v23 didn't compile, v24 found the store's 0-based last-page rule, fixed); `m2/suite-after-resolution-groups-20261124T214107Z/` | **PASS**: 1,000 candidates resolved by a four-page group only when complete, a later candidate left in conflict, a relayed group waiting for its missing page, a wrong digest never applied, maximum-size notes identical in both orders on two replicas, the advisory limit only on local creation; debug build 0 warnings, R1 suite 376/66 | M2-8 |
| M2-9 `LisaTime`'s monotonic clock with boot time | `m2/harness-v26/` (its first run found an overflow capped instead of saturating, fixed in the product); `m2/suite-after-monotonic-clock-20261124T214341Z/` | **PASS**: the boot clock never going back and agreeing with `/proc/uptime` read by another process, saturating arithmetic, the manual clock never going back; R1 suite 376/66 with `LisaTests.so` relinked | M2-9 |
| M2-10 signed change pages and partition cursors (unwindowed partitions) | `m2/harness-v28/` (v27's test roster lacked the replica's own key); `m2/harness-v29/` (v21's table list superseded); `m2/suite-after-change-pages-20261124T215237Z/` | **PASS**: the four cursor cases with trimming, pending operations committed and rejected through a page, a repair deferring then applying a page, partitions with different cursors, a tampered page and a forged entry refused with nothing changed, a waiting edit released by a canonical entry, a restart; debug build 0 warnings, R1 suite 376/66 | M2-10 |
| M2-11 the full snapshot's staged installation (S-06 M2 parts) | `m2/harness-v30/` (first run 7/7); `m2/harness-v31/` (v29's table list superseded); `m2/suite-after-installation-20261124T220211Z/` | **PASS**: installation under writes with searches around a local edit and its rejection, the burst absorbed (backlog 440), above the threshold (3,440 invalidated without applying), 2,048 installs and 2,049 invalidates, a newer page and an older cut, staging across a restart with a page reflected once, a tampered chunk; capture p95 2.6 ms, swap 8.7 ms | M2-11 |
| M2-12 the staged installation under storage pressure and process kills | `m2/harness-v35/` (v32 never built; v33 and v34 each one test-side gap); container `run-20261124T220823Z`; `m2/suite-after-reserve-checks-20261124T221039Z/` | **PASS**: non-capture writes stopping at the reserve while captures save; peak sizes (database 6.4 MB, WAL 4.6 MB, staged 5.4 MB); real SIGKILLs inside the staging-index and swap transactions; on the tmpfs, staging stopped at the reserve, 2,848 captures saved with the ballast, 3 reported not saved, consistent and installed after space returned | M2-12 |
| M2-13 calendar buckets on the replica (S-08 replica part) | `m2/harness-v36/` (first run 6/6); `m2/harness-v37/` (v31's table list superseded); `m2/suite-after-calendar-buckets-20261124T222022Z/` | **PASS**: bucket ranges, the absence rule in both orders with what an older proof shows, windows that don't nest, a rolling window and a move, a page deferred during a bucket repair, a stale relayed page | M2-13 |
| M2-14 partition repairs by generation: the overlay watermark and constant-size publication | `m2/harness-v39/` (v38 didn't compile); v36 and v28 again; `m2/harness-v40/` (v37's table list superseded); `m2/suite-after-repair-generations-20261124T222922Z/` | **PASS**: staged rows invisible until the flip, local changes keeping the watermark, publication 0.67 ms with 10 rows and 1.19 ms with 5,000, a stale snapshot refused and another epoch abandoned, a bucket entering the window, an incomplete repair, cleanup to the published generation | M2-14 |
| M2-15 the planning zone: zone-unverified floating rows and all-day rows in the planning zone | `m2/harness-v43/` (v41 one wrong expectation, v42 a broken manifest); `m2/harness-v44/` (v40's table list superseded); `m2/suite-after-planning-zone-20261124T223742Z/` | **PASS**: all-day rows following the date at UTC+14 and UTC−12 with a fixed UTC call; a zone change marking a floating row and its source unverified until a zone proof, the re-expanded row verified on its own; a migrated row's source unverified on both days; no free time from repairing or uncovered days. S-08's M2 replica part complete | M2-15 |
| M2-16 derived records across a full snapshot's swap | `m2/harness-v46/` (v45 didn't compile); `m2/suite-after-full-snapshot-records-20261124T224312Z/` | **PASS**: absence from the first reader after the swap, delayed older bucket snapshots refused, a page during staging reflected once. S-06's M2 part complete | M2-16 |

The first outcomes passed, so M0 needed no production fix. Every run directory and log is new; first outcomes are kept as recorded.

## 5. Open conflicts, blockers and unavailable evidence

| Item | Status, executor and cause |
|---|---|
| Fedora 45 with Swift 6.3.2 (§4 C8, §8.18 step 2, P-08's toolchain list) | `NOT_RUN_ENVIRONMENT` (Claude; the platform changed; Swift 6.3 has no Debian 13 build). The owner set Swift 6.4.2 on Debian 13 as the baseline |
| E-5, libxml2 2.15 and OpenSSL 4.0 | `NOT_RUN_ENVIRONMENT` (Claude; Debian 13 ships libxml2 2.9.14 and OpenSSL 3.5.9) |
| Rootless engine evidence for G2: UID/GID mapping, secret access | `NOT_RUN_ENVIRONMENT` (Claude; this engine is rootful). Genuine rootless amd64 evidence is still required |
| arm64 | `NOT_RUN_ENVIRONMENT` (Claude; no arm64 environment); R1's historical results only |
| SELinux, VPN and off-VPN reachability over IPv4 and IPv6, D05 | The owner's, on the target host; pending M4 |
| X1: `Apps/Proof`, N-1, E-1, E-2 | **`FAIL`** (owner, reported 2026-11-26T00:34Z). The first Xcode build of `LisaProof` stopped at `ProofNearbyController.swift:130` with "Failed to produce diagnostic for expression". **Attempt 2 requested** at `795b4f3` (§6). Every X1 case waits for the owner's results |
| Apple builds and devices (X2–X7), live providers (LS-1–LS-3) | The owner's sessions; pending their milestones |
| Proton Calendar | Provider capability blocker: no authenticated, private, read-only interface; G4 and G5 stay open (§8.19.6) |
| KF-1, KF-2 | Open, deferred by the owner on 2026-11-23, no waiver |
| Frozen fixtures not yet produced | The raw `sending` queue file and the pruning pair were produced at M3's start (`docs/VERIFICATION-SCENARIOS.md` M3-0). Still to produce: `acceptedByProvider` (R1 trusts only the system store for SMTP, so a controlled server needs another route), `confirmedDelivered` and paired-device flows through `lisa serve`, `inProgress`, model-budget consumption, the capture-title and shared-URL cases, richer revision histories and plan-block actions (due before S-02 and S-13 at M9) |
| Reopening the replica at 0 bytes free | **Decided and done (D-61, `33b0322`).** The owner allowed it on 2026-11-25. At launch the replica empties its ballast and opens once more. That applies on `SQLITE_FULL`, or on the I/O error SQLite reports on a full tmpfs while less than a reserve is free. `releasedBallastAtOpen` and `storageIsAlmostFull` say so, and the ballast is restored when space returns. Tested on a real full tmpfs in the pinned container (M3-D61) |
| SQLite WAL-reset fix | Settled by design (D-55, M2-0): the loaded library isn't shown to carry the fix, so every WAL database has one writer and checkpointer under an exclusive lock and read-only readers; the guard's checks pass. The production image's library is judged the same way at M4 |

**Environment event (2026-11-25T16:23Z–17:33Z): the sixth pause wasn't resumed**
- **What happened:**
  - The guard held pause `P-20261125T122450Z-9de75e` for the 16:20Z reset.
  - From 16:23:05Z every reading failed. The credentials of the usage reader's headless Claude Code had stopped working: its first fetch failed, and later readings fetched nothing.
  - The guard refused eight readings, up to 17:23:11Z, as not fresh, and launched nothing.
  - The VM stopped after the guard's last heartbeat at 17:25:42Z and booted again at 17:32:29Z. The guard doesn't survive a restart.
  - The owner signed in again (`/login`) at about 17:33Z. A fresh reading at 17:39:32Z worked, bound to the same account (`0c503c8f4594e0fb`).
- **Impact:**
  - Nothing was lost. The last writer, `38d24e96-…`, paused cleanly at 12:26Z with everything committed (HEAD `dc86f0a`, clean tree), and no writer ran after it.
  - The run has been idle since 16:23Z.
- **The owner's instruction:** report the interruption (done in the session) and wait for approval before resuming. The guard stays stopped until then, since starting it would launch the pending resume.
- **State at 2026-11-26T00:34Z:**
  - The guard isn't running, the pause is pending and the writer lock is free.
  - HEAD was `dc86f0a` before the X1 record.
  - A fresh reading (`791f946832fc`) showed 0% used, next reset 05:30:00Z.
  - The lease `interactive:312` was taken without `--consume-pauses` for the X1 record and released afterwards.
  - The owner then approved resuming. The seventh resume started at 01:04Z (§9).
- **Weakness found:** the guard tells no one while its readings keep failing. It disarms only after 48 failed readings, about 11 hours with its backoff. Proposed to the owner: a visible notice after three consecutive failed readings.

**Process deviation, recorded (2026-11-26, about 00:35Z, Git):** while finding where X1 results are recorded, this session ran `git ls-files` once, piped into `grep`. It is read-only and changed nothing, but it is outside plan §3's allowed set. Searches use `grep -r` over the tree instead.

**Writer lease lapse (2026-11-24T20:35:00Z–22:52:26Z), found and fixed:**
- **What happened:** at 20:34:58Z Claude Code moved the interactive session into a background job. That forked it as session `d53fb9c3-…` (pid 4804) and ended the interactive process (pid 321). The lease helper saw its owner exit and released the lease at 20:35:00Z.
- **Impact:** M2-15 and M2-16 were written by this one session without the lease. The event log shows no launch and no other acquisition in that interval, and no pause was pending, so no second writer ran.
- **Why it mattered:** guard v1 binds a session lineage (the configured session plus acknowledged launches). It would have rejected this session's pause and its StopFailure, so an automatic resume could not have started.
- **Fix:** guard v2 (`guard/guard_v2.py`, built as new files by `guard/make_v2.py`; v1 is kept) adds `extend-lineage`. It is verified from the session's running process: Claude Code, `--session-id <session>`, `--fork-session`, `--resume <a lineage session>`.
- **Rehearsal:** `guard/rehearsal-v2-20261124T225055Z/REPORT.md`, 14 of 14 scenarios: v1's ten plus four for the extension, its refusals, a forked session's interruption and the binary check.
- **Switch-over at 22:52Z:** v1 disarmed and v2 re-armed; the lineage extended to `d53fb9c3-…` from pid 4804's command line; the lease re-acquired as `interactive:4804`.

**Disk again (2026-11-25T02:07Z):**
- **What happened:** the project volume filled (63 MB free) when regression package v6's build added R1's host and SwiftNIO to the shared scratch path. The build failed, and with it every target. No test ran.
- **Reclaimed:** superseded M1 build output in `.build/` (611 MB, `m3/disk-reclaim-20261125T020802Z.txt`).
- **Workaround:** regression builds now use a scratch path on the container's root volume, `/tmp/lisa-r2-20261124-r2-5462/regressions-scratch` (`m2/run-regressions-v7.sh`), which had 11 GB free. Build output isn't a temporary file (`CONSTRICTION.md`); harness sources, logs and evidence stay in the run directory.
- **Remaining room:** 515 MB on the project volume and 7.2 GB on the root volume.
- **Decided by the owner (2026-11-25):** see "Owner-approved reclaim" below.

**Disk (2026-11-24T23:27Z):**
- **What happened:** the volume fell to 349 MB free. Each harness's own `.build` rebuilt on every regression round, and switching the shared scratch path's index setting rebuilt it once more.
- **Reclaimed:** superseded SwiftPM output from before this run was removed from `.build/`: `.build/out` and `.build/toolchain-6.4.3`, 7.1 GB (`m2/disk-reclaim-20261124T232752Z.txt`). That is ordinary build output under `CONSTRICTION.md` and lies outside the run directory. 7.5 GB were then free.
- **Since then:** new harnesses share one scratch path (`m2/harness-scratch-late`). Regressions run as one package with byte-identical copies of the current harnesses' sources (`m2/make-regressions-v1.py`, `-v2.py`), with v35 and v47 in their own packages.
- **Decided by the owner (2026-11-25):** regenerable build output may be removed.

**Owner-approved reclaim (2026-11-25T05:59Z):**
- **Override:** plan §10.2's no-removal rule, for SwiftPM build output only (DEVELOPMENT-ENVIRONMENT-REPORT.md §14).
- **Removed:** 43 directories, 30.72 GB:
  - every `m2/harness-vN/.build`, from v11 to v46;
  - `m2/harness-scratch-late`;
  - `m1/harness/.build`, `m1/harness-v2/.build` and `m1/proof-proposal/cert-check/.build`;
  - the `build-debug`, `build-release` and harness scratch folders of `m1/clean-20261124T134046Z`, `m2/clean-20261124T225253Z` and `m2/clean-20261124T233606Z`.
- **Kept:** the frozen R1 builds under `m0/` (`r1-src/.build` and the frozen-client harnesses), and `m2/harness-v42/.build`, which is not shown to be SwiftPM output.
- **Free space:** 514 MB before, 31,108 MB after.
- **Record:** `.tmp/r2/20261124-r2-5462/reclaim-20261125T055921Z-planned.tsv` (each path, size, newest file and recovery command) and `…-done.md`.
- **Recovery:** each is SwiftPM output; run the command in its row. For a clean run, that is the build line of its `matrix.sh` into a new path, never re-running `matrix.sh`, whose logs are evidence.

**Process deviation, recorded (temporary files):** harness v47's test file was edited in place once, before its first build (a `World` value moved into each test). The rule asks for a new version. Every later fix went into a new version.

**Record note:** the times written in the headers of harnesses v26–v51 are estimates, up to 80 minutes late (v46). The log file names come from the clock and are exact. Likewise, M3 harness v34's header and `m2/make-regressions-v19.py`'s docstring say "01:4xZ", but they were written at about 01:35Z and 01:37Z on 2026-11-26. M3 harness v35's header says "about 01:55Z" (written about 01:52Z), v37's "about 02:05Z" (about 02:04Z) and v38's "02:08Z" (02:06Z). The checkpoint's "design (2026-11-26T02:00Z)" was written at about 01:58Z and is corrected in place.

**Record note (2026-11-26, M3-6b step 3a):** four temporary headers state times ahead of the clock. They are harness v45's "02:58Z" and v46's "03:00Z", and the docstrings of `m2/make-regressions-v25.py` ("03:01Z") and `make-regressions-v26.py` ("03:03Z"). They were written between about 02:53Z and 02:56Z: harness v45's build log is named `20261126T025359Z`, and the regression run `20261126T025545Z`. Temporary files aren't edited, so this note is the correction. The rule stays: read `date -u` before writing any time.

**Found and fixed in M2-20:** the replica's duplicate rules looked only at its journal. A relayed copy of an operation known from canonical state became a pending overlay, and a changed body or a reused triple raised no security event. Canonical operations now keep their origin triple, and the rules consult canonical state too (`docs/VERIFICATION-SCENARIOS.md` M2-20).

**Environment event (2026-11-24, the VM stopped):** the sandbox VM stopped after 16:57:14Z (the guard's last heartbeat) and before 17:53Z, when the guard would have taken its post-reset reading; it booted again at 20:25:22Z. The guard and its pending pause `P-20261124T135657Z-39d87a` didn't run in between, so nothing launched. The owner resumed Claude in the original interactive session; Claude inspected the files and processes (HEAD `d31a943`, clean tree, no writer, 21 GB free, toolchains and Docker present), took a fresh reading, took the writer lease with `--consume-pauses` at 20:33:37Z and restarted the guard (pid 2746). Nothing was lost: the last commit before the stop was the pause checkpoint.

**Environment event (2026-11-24T13:47Z):** the project volume filled (49 GB, 5.6 MB free) and a link failed. The SwiftPM scratch outputs of superseded builds under `.build/` were removed (24 GB). They are ordinary build output, not temporary files (`CONSTRICTION.md`); their logs and runner hashes are kept in `.tmp/`, which wasn't touched. Routine builds now reuse `.build/r2-run`, and storage is checked before large builds.

**Process deviation, recorded (temporary files):** plan §10.2 says nothing in a run directory is overwritten. Until about 09:00Z this run edited temporary scripts in place while developing them: `usage/usage_read.py`, `usage/statusline_tap.py`, `guard/guard.py`, `guard/rehearse.py` and `m1/harness/Package.swift`. No log, reading, report or evidence file was overwritten, but the first guard rehearsal (`rehearsal-20261124T080243Z`) ran an earlier `guard.py` than the second (`rehearsal-20261124T080830Z`) and the live guard, which run the corrected one. Since then every revision of a temporary file is a new file (`harness-v2/`, `EnvelopeTestsV2`, `MerkleTestsV2`, `NOTES-2.md`).

**Process deviation, recorded:** before 08:08Z this run used five read-only Git commands outside the plan's allowed set (§3): `git worktree list`, `git merge-base --is-ancestor`, `git ls-files`, `git rev-list --max-parents=0` and `git symbolic-ref`. None changed anything. Each was replaced (by `rev-parse`, `log` or a `git show` walk), and only `status`, `diff`, `log`, `show`, `rev-parse`, `add` and `commit` are used since.

## 6. Pending owner sessions and experiments

**X1 is requested (2026-11-24T13:50Z):** entry point `Apps/Proof` (scheme `LisaProof`, test plan `X1`) with `swift run lisa-verify quickstart`; the sheet is `Harness/docs/SETUP-APPLE.md` (prerequisites, build and signing, roster, the nine nearby cells for both designs, the nine fetch-probe cases on each device, the three E-2 builds, expected observations, and the redacted export to return). Cases: `OV-NEAR-{MI,MP,IP}-01..03` (paired), `OV-APPLE-X1-01..03`, `OV-APPLE-X1-FETCH-01..09`. Still to come: X2 (after M3), X3 (after M5, with the R1 Mac build for X7), X4 (after M6), X5 and LS-1/LS-2 (after M7), X6 and LS-3 (after M8), X7 (at M9), target-host checks (from M4). None is requested yet; each gets its entry point, prerequisites, case IDs, expected observations and the redacted results to return when its milestone delivers it.

**X1, first attempt: `FAIL` at the build** (the owner, reported 2026-11-26T00:34Z)
- **The owner's report:** "`Xcode` reported `Failed to produce diagnostic for expression; please submit a bug report` at `Apps/Proof/Nearby/ProofNearbyController.swift`, line `130`. The Xcode build failed."
  - It came in the Claude session, with no harness export.
  - Not stated: the Xcode version, the destinations, the commit and any other errors.
  - The verbatim report, with the analysis below: `.tmp/r2/20261124-r2-5462/owner/x1-attempt1-20261126T0034Z-v2.md`. It supersedes the first version beside it and corrects it on three points.
- **Line 130:** the file is unchanged since `b5b69b6`, so every commit the owner could have fetched has this line.
  - Design A's listener builds its PSK selection probe as `configuration.probeSelectionBlock ? { [weak self] hintBytes in Task { @MainActor [weak self] in self?.log("… \(hintBytes.map(String.init) ?? "none")") } } : nil`, against the declared type `(@Sendable (Int?) -> Void)?`.
  - The types agree with `DesignAParameters.make`. The type checker found no solution and couldn't name an error. That is a compiler defect on this shape of expression, and it may also hide a real error.
  - No other Swift file under `Apps/` or `Harness/Sources` uses a closure as a branch of `? :`.
- **Why M1 missed it:** M1-8 type-checked only the 38 files without an Apple-only import. This file imports `Network`, so it had syntax checks only. X1 was its first type-check.
- **Status:**
  - The `LisaProof` build: `FAIL` (owner).
  - `OV-APPLE-X1-01`–`03` (E-2) can't pass until a fixed build passes.
  - The nearby cells (N-1), the fetch probe (E-1) and test plan `X1` weren't reached.
  - N-1, E-1 and E-2 stay open, so M6's nearby transport and M7's retrieval design keep waiting (plan §9). Other work doesn't wait.
- **Next, once the owner approves resuming (not done now):**
  1. Rewrite the expression with an explicitly typed closure and no `? :` (the proposed code is in the evidence note).
  2. Type-check `Apps/Proof`'s Apple-importing files on Linux against stand-ins, as M1-8 did for the portable files, so the next attempt doesn't stop at the following error.
  3. Commit, and request X1 again, naming the new commit.

  The Xcode version and any other errors in the build log would help.

**X1 attempt 2 is requested (2026-11-26T01:29Z)** at commit `795b4f3` or later.
- **Unchanged:** the entry point, sheet and cases, as above.
- **What changed:**
  - The fix for line 130 (`f03cf24`).
  - The proof views' three `Binding(get:set:)` closures became key-path bindings (`0528fc3`–`795b4f3`). They compile whichever way the SDK annotates those closures.
- **What was checked:** the whole target type-checks on Linux (Swift 6.4.2 and 6.4.3) against framework stand-ins.
  - The iOS-like and macOS-like passes: 0 errors, 0 warnings.
  - The baseline with the old file: exactly attempt 1's error.
  - Six negative controls: all caught.
  - Details: `docs/VERIFICATION-SCENARIOS.md` M1-8b.
- **Still unknown:** the real SDK may differ from a stand-in, and Xcode's Swift may be older than 6.4.
- **If the build fails again,** send the output of `xcodebuild -version` and every error with its file and line (the sheet's §2 now says how), so one fix covers them all.

## 7. Permissions in force

- **Engine:** the rootful Docker daemon inside `lisa.lab` (owner, 2026-11-24; P-02, P-03, account-free P-09a at their milestones).
- **P-07:** any R1 test or test-support change needs the owner's approval of a request naming the file, reason and evidence.
- **Dependencies:** existing versions may change after the freeze when necessary or beneficial (swift-crypto 5.1.2 first, SwiftNIO 2.105.1 assessed), each with revisions, rationale, lockfile change and regression results. **P-08** stays conditional on N-1 and on the owner's approval of the exact swift-certificates pin. **P-09a:** Proton Mail Bridge 3.27.2 on amd64.
- **Build output (owner, 2026-11-25):** regenerable build output may be removed, inside the run directory too, now and later. Each report states the override, the deleted files and the recovery steps.
- **The replica's ballast (owner, 2026-11-25):** it may be released to open the replica at launch (D-61), with the same reporting.
- **Kept by the owner:** the host, accounts, image publication, production deployment, real-data cutover, the Apple Developer account, every live provider action and every device session.

## 8. Last buildable checkpoint

**`1621ecb`** (`Sources/LisaAPI/LegacyRouting.swift`, M3-6b step 3b-i's holds with the shared answers, D-75):
- **Build and suite:** the debug build with tests has 0 warnings and 0 errors, and the R1 suite passes 376/66 (`m3/suite-after-preference-answers-20261126T031143Z/`). Lint is clean on the changed files, apart from R1's own `Package.swift` line.
- **Harness:** M3 harness v48 passes 12/12.
- **Regressions:** regression package v28 (`m2/run-regressions-v29.sh`, run `m2/regressions-run-20261126T031158Z/`) passes all 29 targets, and v35 and v47 pass too.
- **Before it, `e920b58`**, holds alone: the suite at `m3/suite-after-holds-20261126T030554Z/`, harness v47 12/12 and regression package v27, all passing.
- **The spans:** `9b09007` to `e920b58`, then `40ec2d7` to `1621ecb`. The commits are ordered so that each one builds, but the build was checked only at each span's end.

Before it, **`8313d30`** (`Sources/LisaAPI/LegacyRouting.swift`, M3-6b step 3a's converted `PATCH /v1/preferences`, D-74):
- **Build and suite:** the debug build with tests has 0 warnings and 0 errors, and the R1 suite passes 376/66 (`m3/suite-after-preference-conversion-20261126T025433Z/`). It was built from the working tree, which held the span's final content uncommitted. Lint is clean on the nine changed files, apart from R1's own `Package.swift` line.
- **Harness:** M3 harness v45 passes 10/10.
- **Regressions:** regression package v26 (`m2/run-regressions-v27.sh`, run `m2/regressions-run-20261126T025545Z/`) passes all 29 targets, and v35 and v47 pass too.
- **The span:** `aa0ec19` to `8313d30`. The commits are ordered so that each one builds, but the build was checked only at the end.

Before it, **`44cb3ed`** (`Sources/LisaReplicaStore/ReplicaPreferences.swift`, M3-6b's preferences at Core and on a replica, D-73):
- **Build and suite:** the debug build with tests has 0 warnings and 0 errors, and the R1 suite passes 376/66 (`m3/suite-after-preference-ledger-20261126T022947Z/`). Lint is clean on the eight changed files.
- **Harness:** M3 harness v43 passes 5/5.
- **Regressions:** regression package v24 (`m2/run-regressions-v25.sh`, run `m2/regressions-run-20261126T023013Z/`) passes all 31 targets, and v35 and v47 pass too.
- **The span:** `f404e2c` to `44cb3ed`. The build was checked at its end, not at each commit.

Before it, **`fc1c17f`** (`Sources/LisaMerge/PreferenceMergeState.swift`, M3-6b's preference model, D-73):
- **Build and suite:** the debug build with tests has 0 warnings and 0 errors, and the R1 suite passes 376/66 (`m3/suite-after-preference-model-20261126T022139Z/`).
- **Harness:** M3 harness v41 passes 7/7.
- **Regressions:** regression package v23 (`m2/run-regressions-v24.sh`, run `m2/regressions-run-20261126T022204Z/`) passes all 27 targets, and v35 and v47 pass too.

Before it, **`6cc8073`** (`Sources/LisaAPI/LegacyRouting.swift`, M3-6a's converted `PATCH /v1/tasks/{id}`, D-72):
- **Build and suite:** the debug build with tests has 0 warnings and 0 errors, and the R1 suite passes 376/66 (`m3/suite-after-converted-patch-final-20261126T020726Z/`). Lint is clean on the nine changed files.
- **Harnesses:** M3 harness v38 passes 15/15, and M3 harness v39 passes 7/7. v39 is M2 harness v15's tests with an expectation that D-72 superseded.
- **Regressions:** regression package v22 (`m2/run-regressions-v23.sh`, run `m2/regressions-run-20261126T021223Z/`) passes all 26 targets, and v35 and v47 pass too. Package v21's run found the superseded expectation (`m2/regressions-run-20261126T020805Z/`).
- **The span:** `ae0c52d` to `6cc8073`. Each commit builds.

Before it, **`12bd3fb`** (`Sources/LisaAPI/APIRouter.swift`, M3-6a's converted `POST /v1/tasks`, D-71):
- **Build and suite:** the debug build with tests has 0 warnings and 0 errors, and the R1 suite passes 376/66 (`m3/suite-after-converted-create-committed-20261126T015435Z/`). Lint is clean on the changed files, apart from R1's own `Package.swift` line.
- **Harness:** M3 harness v36 passes 7/7.
- **Regressions:** regression package v20 (`m2/run-regressions-v21.sh`, run `m2/regressions-run-20261126T015451Z/`) passes all 26 targets, and v35 and v47 pass too.
- **The span:** `f4879b6` to `12bd3fb`. Each commit builds.

Before it, **`89fcb1a`** (`Sources/LisaReplicaStore/ReplicaStore.swift`, M3-6a's observed horizons on replicas, D-69):
- **Build and suite:** the debug build with tests has 0 warnings and 0 errors. The R1 suite passes 376/66 (`m3/suite-after-replica-horizon-20261126T013338Z/`). Lint is clean on the eight changed files.
- **Harness:** M3 harness v34 passes 20/20.
- **Regressions:** regression package v19 (`m2/run-regressions-v20.sh`, run `m2/regressions-run-20261126T013734Z/`) passes all 25 targets, and v35 and v47 pass too.
- **The span:** `53e2a5a` (`ChangeEntry`) to `89fcb1a`. Each commit builds. Until `a59ce54`, a snapshot swap drops the new columns, but nothing reads them before `89fcb1a`.

Before it, **`6b3ec91`** (`Sources/LisaLegacyRequests/LegacyChildSet.swift`, M3-6a's observed horizons at Core, D-69):
- **Build and suite:** a full debug build with tests has 0 warnings, and the R1 suite passes 376/66 with schema v11 (`m3/suite-after-observed-horizon-20261125T121653Z/`). Lint is clean on the six changed files.
- **Harness and migration check:** M3 harness v33 passes 15/15. `m3/check-migration-v11-v1.py` passes v11's copy path on a v10-shaped database.
- **Regressions:** regression package v18 (`m2/run-regressions-v19.sh`, run `m2/regressions-run-20261125T122040Z/`) passes all 25 targets, and v35 and v47 pass too.
- **A commit that doesn't pass alone:** `1a8436e` (`Migrations.swift`) builds, but its projections fail until `2399cda`.

Before it, **`47f32cf`** (`Sources/LisaSyncProtocol/OperationEnvelope.swift`, M3-6a's observed projection revision): a full debug build with tests has 0 warnings and the R1 suite passes 376/66 (`m3/suite-after-observed-revision-20261125T120825Z/`); M3 harness v31 passes 9/9. Regression package v17 (`m2/run-regressions-v18.sh`, run `m2/regressions-run-20261125T120847Z/`, with harness v31 in place of v30) passes all 25 targets, and v35 and v47 pass too; 23.5 GB were free at its end.

Before it, **`bac4ab8`** (`Sources/LisaCoreLedger/CoreLegacyParents.swift`, M3-6a's projection-revision map):
- **Build and suite:** a full debug build with tests has 0 warnings, and the R1 suite passes 376/66 with schema v10 (`m3/suite-after-projection-revisions-20261125T120421Z/`). Lint is clean.
- **Harnesses:** M3 harness v30 passes 8/8; v28 fails its two value checks, as D-68 records.
- **Regressions:** regression package v16 (`m2/run-regressions-v17.sh`, run `m2/regressions-run-20261125T120453Z/`) passes all 25 targets, and v35 and v47 pass too.
- **Commits that don't build alone:** `42fe54f` (`OperationOrigin.swift`) needs `abf192f`. `2b4449e`'s message says "add:" for a function added to an existing file; there are no amends.

Before it, **`1bcd470`** (`Sources/LisaSyncHTTP/HTTPTrustRequests.swift`, M3-5d's device key rotation):
- **Build and suite:** a full debug build with tests has 0 warnings, and the R1 suite passes 376/66 with schema v8 (`m3/suite-after-device-keys-20261125T114317Z/`). Lint is clean.
- **Harnesses:** M3 harnesses v22 (16/16) and v16 (6/6) pass.
- **Regressions:** regression package v14 (`m2/run-regressions-v15.sh`, run `m2/regressions-run-20261125T114435Z/`) passes all 24 targets, and v35 and v47 pass too.
- **One commit doesn't build alone:** `5b63c22` (`CoreLedger.swift`) needs the next one, `ace09a9`.

Before it, **`6e55294`** (`Sources/LisaCoreLedger/CoreExportKeys.swift`, M3-5d's export-key rotation): a full debug build with tests has 0 warnings and the R1 suite passes 376/66 at this HEAD (`m3/suite-at-head-20261125T073144Z/`); M3 harness v19 passes 13/13. The documents follow up to the pause.

Before it, **`1daf65f`** (`Package.swift`, formatting only, after M3-4b and M3-4c):
- **Build and suite:** a full debug build with tests has 0 warnings, and the R1 suite passes 376/66 at this HEAD (`m3/suite-at-head-20261125T072924Z/`). The whole-tree lint shows only R1's own finding (`Package.swift` AddLines, now line 196; `m3/lint-tree-20261125T072843Z.log` was taken before the wrap, and shows the three wrapped lines too).
- **Harnesses:** M3 harness v18 passes 12/12 and v16 6/6.
- **Release build and regressions:**
  - A release build of the whole package has 0 warnings (`m3/release-build-20261125T072841Z/`).
  - Regression package v11 (`m2/run-regressions-v12.sh`, run `m2/regressions-run-20261125T072713Z/`) passes all 24 targets, and v35 and v47 pass too.

Before it, **`26b9063`** (`Sources/LisaSyncHTTP/HTTPTrustRequests.swift`, M3-5c's last code commit):
- **Build and suite:** a full debug build with tests has 0 warnings, and the R1 suite passes 376/66 (`m3/suite-after-reset-challenges-20261125T071556Z/`). Lint is clean.
- **Harnesses:** M3 harnesses v15 (10/10), v14 (5/5) and v16 (6/6) pass.
- **Regressions:** regression package v9 (`m2/run-regressions-v10.sh`, run `m2/regressions-run-20261125T071659Z/`) passes all 24 targets, and v35 and v47 pass too.

Before it, **`fbfd1ec`** (`Sources/LisaSyncHTTP/HTTPEnrollmentTransport.swift`, M3-5a and M3-5b; the documents follow up to `a4f4109`):
- **Build and suite:** a full debug build with tests has 0 warnings, and the unmodified R1 suite passes 376/66 with schema v6 (`m3/suite-after-enrollment-formatted-20261125T065446Z/`). `swift format lint` is clean on every new and changed file.
- **Harnesses:** M3 harness v10 passes 8/8 (enrollment over loopback HTTP), and harness v14 passes 5/5 (S-04 and S-05 over real TLS with libcurl).
- **Regressions:** regression package v8 (`m2/run-regressions-v9.sh`, run `m2/regressions-run-20261125T070034Z/`) passes all 24 targets, and v35 and v47 pass too.

Before it, **`33b0322`** (`ReplicaStore.swift`, D-61). A full debug build with tests has 0 warnings, and the R1 suite passes 376/66 (`m3/suite-after-ballast-at-open-io-20261125T060530Z/`). M3 harness v7 passes 2/2 on the host and 1/1 on a full tmpfs in the pinned container (`m3/container-20261125T0604Z/run-20261125T060502Z/`). Regression package v6, run by `m2/run-regressions-v7.sh`, passes in `m2/regressions-run-20261125T060539Z/`.

**`9cc02f4`** (`Package.swift`, the LisaCoreAPI, LisaSyncEngine and LisaSyncHTTP targets). The full debug build with tests has 0 warnings, the R1 suite passes 376/66, M3 harness v5 passes 2/2, and regression package v6 passes with its 23 targets plus v35 and v47 (`m2/regressions-run-20261125T020817Z/`, scratch on the root volume). Before it: **`aade818`** (`ReplicaStore.swift`, Core receipts verified on a replica). The full debug build with tests has 0 warnings, the R1 suite passes 376/66, M3 harnesses v3 and v4 pass, and regression package v5 passes with its 22 targets plus v35 and v47 (`m2/regressions-run-20261125T015607Z/`). Before it: `1286627` (Core snapshots), then **`13736ee`** (`Package.swift`, the LisaCoreLedger target). A full debug build with tests has 0 warnings, and the unmodified R1 suite passes 376/66 with schema v5. M3 harness v2 passes 8/8, and regression package v4 passes with all 20 targets plus v35 and v47 (`m2/regressions-run-20261125T014819Z/`). Before it:

**M2's clean-checkout checkpoint:** `815bbbc`, reconstructed byte-exact into `m2/clean-20261124T233606Z/tree`. Debug and release have 0 warnings, the R1 suite passes 376/66, fixtures 9/9, lint shows only R1's finding, and the 21 current harnesses pass (108 tests). Its last code commit is the following one:

`cdced83` (`ReplicaStore.swift`, the duplicate rules against canonical state). A full debug build with tests has 0 warnings, and the unmodified R1 suite passes 376 tests in 66 suites (Swift 6.4.2). Harness v51 (4) passes, and so does regression package v2 with its 19 targets (v6, v9, v10, v13, v15, v19, v20, v25, v26, v28, v30, v36, v39, v43, v46, v48, v49, v50, v51), with v35 and v47 in their own packages (run `m2/regressions-run-20261124T233307Z/`). Before it:
- `79e44f1`, peer custody;
- `9286c07`, revocations;
- `642e955`, the interim clean-checkout boundary: debug and release 0 warnings, the R1 suite 376/66, fixtures 9/9, 17 harnesses, lint as R1's only; `m2/clean-20261124T225253Z/`;
- `e563114`, derived records in full snapshots;
- `c5b5cb1` (the planning zone), `e838a98` (calendar buckets), `177763a` (reserve checks), `ab0f695` (the staged snapshot installation), `8afac3b` (change pages and partition cursors), `437ca91` (`LisaTime`'s monotonic clock), `3fb9b7f` (paged resolution groups), `cd37d4f` (`LisaLocalSearch`), `09cf01a` (the effective view and persisted causal release), `4e0c1e3` (the item payload schemas and `TaskMergeState`), `0aac9d1` (the reader monitor and the capture path, with the container cases), `818fe3c` (`LisaReplicaStore`'s first span), `386a738` (`CausalRelease`) and `c9fed41` (the WAL guard). `d0a9e53` is M1's clean-checkout checkpoint (debug and release, R1 suite, fixtures 9/9). Later commits change documents only.

## 9. Quota monitoring, the guard, pause and resume

- **Readings.** `.tmp/r2/20261124-r2-5462/usage/usage_read.py` starts a headless Claude Code process that sends only the SDK `get_usage` control request (no prompt, no model call); Claude Code fetches `/api/oauth/usage` itself. A reading counts as fresh only if that fetch happened inside the process; values served from Claude Code's shared 60-second cache are refused. While Claude works, the status-line tap records the session's own rate-limit fields after every response. Logs: `usage/readings.jsonl`, `usage/statusline.jsonl`.
- **Proved on 2026-11-24:** a fresh reading during development (07:52:11Z, 0% used, reset 12:49:59.72Z, matching the status line) and a fresh reading by a detached process while Claude was idle after its turn ended (08:12:02Z, 6%; no transcript entry and no model request during the reading).
- **The guard.** `.tmp/r2/20261124-r2-5462/guard/guard.py`, one detached process, bound to this account (hash `0c503c8f4594e0fb`), session lineage, sandbox checkout and run ID. It waits without model calls for a recorded quota pause or a verified quota interruption, confirms the reset with a fresh reading after the reported reset plus 180 s, checks the other plan windows, and launches one writer (`resume-launcher.sh`: a forked resume of the session) under the repository writer lock. The interactive session holds that lock through a lease helper. Rehearsed with simulated readings, a short clock and a harmless launcher at 08:02Z and 08:08Z: 10 of 10 scenarios passed. The real launcher has not run yet; its first use will be the first post-reset resume.
- **Owner commands.** Inspect: `.tmp/r2/20261124-r2-5462/guard/guardctl status`. Stop: `guardctl stop --reason "<why>"` or `touch .tmp/r2/20261124-r2-5462/guard/live/STOP`. After a VM restart nothing restarts by itself: run `guardctl daemon --detach`, or resume Claude, which restarts it. A guard stopped by the owner restarts only with `--rearm "<reason>"`.
- **Pause procedure (the owner's instruction of 2026-11-25: use each five-hour window to about 90%, and never hit the limit by accident).**
  - **Keep working past 80%.** A long span is not a reason to stop early: split it at a safe step and leave the exact next action, and the guard resumes it after the reset. Pauses at 60–72% left a quarter of the window unused.
  - **From about 85%,** start nothing that can't finish by about 90% (a build-and-regression round costs about 3–6 points). Finish or checkpoint the current step, then pause, so the pause procedure, which costs 2–4 points in a long context, completes by about 88–90%.
  - **Readings:** take a fresh one before each expensive step above 80%, and run the watchdog at 85% (`usage/watchdog_v1.py --threshold 85`).
  - **Before pausing: account for running processes, update this file, write a new `.tmp/r2/20261124-r2-5462/pause-<UTC>-<unique>.md` (HEAD, unfinished work, evidence, owner checks, measured usage and reset, the exact next safe action), record it with `guard.py pause`, release the writer lease, end the turn.
- **Batch sizing.** Two concurrent agents plus this session used 11 points of the window in 4 minutes on 2026-11-24 (08:36–08:40Z). Agents now run one at a time unless usage is low. A background watchdog that makes no model calls wakes the session at 85% for the final steps; stop it before pausing, so that no notification wakes a session that is no longer the writer.
- **Evidence for the owner.** `python3 .tmp/r2/20261124-r2-5462/export/make_bundle.py` writes a redacted `bundle-<UTC>.tar.gz` with its SHA-256 (it refuses to package if a canary survives). To copy one out: publish a port once on the host (`sbx port publish lisa.lab 8765:8765`), ask Claude to run `export/serve-bundle.sh`, then `curl -fO http://localhost:8765/<bundle>.tar.gz`.
- **The first real resume (2026-11-24):** the guard recorded pause `P-20261124T094325Z-14b7b7` at 09:43Z, took a fresh reading at 12:53:00Z (0%, reset confirmed after 12:49:59Z plus the 180 s buffer) and launched `L-3930e57701`, a forked headless resume of the session; it was acknowledged at 12:53:07Z by session `d0d5cdce-07e8-48a9-a66e-d38baa446cdf`, which is the writer since. Its fresh reading at 12:54:02Z showed 2%, next reset 17:49:59Z. A headless session runs no status line, so its readings come from `usage_read.py` alone.
- **The third resume (2026-11-24T20:33Z, manual, after the VM restart):** fresh reading 20:33:29Z, 2% used, next reset 2026-11-25T01:20:00Z; lease `interactive:321` (holder pid 2737) consumed `P-20261124T135657Z-39d87a`; the guard restarted as pid 2746 with no pending pause. A new alarm, `usage/watchdog_v1.py` (reads the status-line log only, no model call), ends a background task at 70% so the session sees it.
- **The third pause (2026-11-24T23:44Z, quota):** at M2's boundary, with 72% used (reading `331e864540fb`, 23:42:53Z) and the reset at 2026-11-25T01:20:00Z. The watchdog was stopped, the pause recorded with `guardctl-v2 pause`, and the lease released. Guard v2 (pid 197451) takes a fresh reading after the reset plus 180 s, then launches one forked resume of session `d53fb9c3-…`.
- **Guard v2 (since 22:52Z):** use `.tmp/r2/20261124-r2-5462/guard/guardctl-v2` (`status`, `stop`, `daemon --detach`, `acquire`, `release`, `pause`, `extend-lineage`). The launcher still calls v1's `guard.py ack` and `pause`, which write the same events. When a session runs under a new session ID (an interactive session moved to a background job), run `guardctl-v2 extend-lineage --owner-pid <its claude pid>` and then take the lease. The lineage is now `4e52d1e9-…`, `d0d5cdce-…` and `d53fb9c3-…`.
- **The fourth resume and fifth pause (2026-11-25):** guard v2 launched `L-64486886ba` (session `30b63dd0-89d3-45d0-b885-bb4305d22093`, forked from `a360702d-…`) after the 06:20Z reset; it acknowledged at 06:23:39Z with 16% used.
  - **Work:** M3-5a to M3-5c, M3-5d's expiry, renewal and export-key items, and M3-4's leftovers, from 16% to 76%.
  - **The pause:** at 07:35Z (reading `0b0605d5b94c`, 76%, reset 11:20:00Z), recorded with `guardctl-v2 pause`. The launch wrapper releases writer.lock when this session exits.
- **The fifth resume and sixth pause (2026-11-25):** guard v2 confirmed the 11:20Z reset with a fresh reading at 11:23:01Z (0%) and launched `L-fc7f9168cc`. It was acknowledged at 11:23:26Z by session `38d24e96-7ad7-4d63-ba8d-887352afac4e`, with 10% used at 11:24:02Z.
  - **Work:** M3-5d's signing-key and device key rotation, then M3-6a up to Core's observed horizons, from 10% to about 85%. The context was compacted once, at about 12:10Z.
  - **The cost:** 61 points in 45 minutes with the long context before the compaction (11:24Z–12:09Z), and about 8 points for the whole observed-horizon step after it (12:12Z–12:22Z: code, build, suite, two harness versions, regression v18 and the records).
  - **The pause:** at about 12:26Z for quota, with the exact next action in §11. It is recorded with `guardctl-v2 pause`; the pause note and the final reading are named in the guard's `pause_recorded` event. The launch wrapper releases writer.lock when this session exits.
- **The seventh resume (2026-11-26T01:04Z, manual):**
  - **Why manual:** the sixth pause wasn't resumed by the guard (§5: failed readings from 16:23Z, then the VM restart). The owner asked for a report, then approved resuming.
  - **The steps:**
    - a fresh reading at 01:04:19Z: `12ad2fa98961`, 4% used, next reset 05:30:00Z;
    - the lease `interactive:312` (holder pid 17960) with `--consume-pauses`, which consumed `P-20261125T122450Z-9de75e`;
    - the guard restarted (pid 17963) with no pending pause;
    - the watchdog at 85% (`watchdog_v1.py --threshold 85 --max-hours 5`, a background task).
  - **Why this session:** the resume runs here, in the owner's interactive session, not as a forked resume of `38d24e96-…`. Its first work, X1 attempt 2, had been analyzed in this session.
- **Resume.** Only a recorded quota pause or a verified interruption is resumed, once a fresh reading confirms usable capacity and the previous writer released the lock. Resuming first inspects files and processes. A manual resume takes the lease with `--consume-pauses`, so the guard never launches a second writer.

## 10. Owner action ledger

No live action or external submission has been requested or performed in this run. **Owner check requested:** X1 (§6), on the owner's devices only. It involves no account, provider or real action, so the action ledger records none. Its first attempt failed at the build (reported 2026-11-26), before any device ran. Attempt 2 is requested at `795b4f3`.

## 11. Next steps

**Done first on resuming (2026-11-26T01:04Z–01:29Z):** the X1 build fix, the whole-target Linux type-check (D-70) and X1 attempt 2's request (§6). **Now:** M3-6a's replica side, below.

1. **M3 — Core, v1 and the direct HTTPS path (in progress).** M3-0, the frozen fixtures due before S-01, is done (2026-11-25T01:28Z). The spans, in order, each with its harness, regressions and records:
   1. **M3-1, done** (`docs/VERIFICATION-SCENARIOS.md` M3-1; the receipt's vector and the replica's verifying receipt path followed in M3-3). **Schema v5 and the Core ledger's intake (§8.4.1, §8.2.1–§8.2.2 at Core):**
      - `LisaStore` migration 5 adds the ledger tables, plus a public way to write records and ledger rows in one transaction (R1's `RecordSession` is internal).
      - The new `LisaCoreLedger`: intake in one write transaction with a savepoint per operation, covering bounds, dataset and epoch; signature, digest and the duplicate rules; authorization by the roster resolver; dependencies with release markers (as the replica's persisted release, Core tables); merge; the projection into R1's `tasks` records; the change-log entry; and the final receipt.
      - Core-signed receipts: a LisaSyncProtocol type and a new LisaTrust domain. The replica gains a verifying receipt path, which strengthens L15.
      - Receipt lookup (L14).
      - The projection follows §8.3.4: deadline earliest, estimate longest, priority highest, splittable false, title by display order. It needs R1's `LisaTask` fields (`changeSequence`, `revision`, `ownerCorrected`, `TaskID`) read from R1's code before writing it.
   2. **M3-2, the change feed (§8.4.2):** Core builds signed change pages per partition from the change log. The test is end to end, Core to a replica, in process.
   3. **M3-3:** full snapshots and bucket snapshots from Core (§8.4.3). Full snapshots of unwindowed partitions are done (`docs/VERIFICATION-SCENARIOS.md` M3-2). Bucket snapshots and repairs from Core come with the calendar change feed (span 2).
   4. **M3-4, first slice done** (`docs/VERIFICATION-SCENARIOS.md` M3-4). Still to do: TLS with the libcurl pin transport, the 512 KiB per-path limit (D-60), and capabilities negotiation. `LisaSyncHTTP`, `LisaCoreAPI` v2 (§8.12.1), and `LisaSyncEngine`'s Core session (§8.6.5), end to end against the real TLS server. A read-only survey of R1's HTTP stack (2026-11-25T02:00Z) found:
      - **Server:** SwiftNIO `APIServer` (`Sources/LisaAPIServer`). Its handler is `(APIRequest, APIPeer) async -> APIResponse`. `HostAPIServer.start(for:limits:)` (`Sources/LisaHost/HostAPIServer.swift:28-46`) wires one closure for the device listener (`host.settings.api`: plain loopback, reverse proxy, or TLS) and the owner listener (`127.0.0.1:0`, plain).
      - **Seam:** a defaulted `v2` handler parameter there, tried first for `/v2/` paths and returning nil to fall back to R1's router. That keeps R1's typed 404 for `/v2/` through the in-process router, which `L20APIValidationTests.swift:162-184` pins.
      - **Device authentication:** `Authorization: Bearer <credential>`, through the public `LisaApplication.authenticateDevice(credential:)`, which returns a `DeviceRegistration`. A 401 answers with `{"code":"unauthenticated",…}`.
      - **Body limit:** `APIServerLimits.maxBodyBytes` = 256 KiB, server-wide, checked before routing (`RequestAssembler.swift:39-41,69-73`). A larger v2 limit (512 KiB for `POST /v2/operations`) needs a per-path hook. Raising the global limit would break `L20APINetworkTests.swift:157,203-207`, which expects 413 and a closed connection.
      - **Client:** `URLSessionTransport` refuses paths outside `/v1/` (`HostEndpoint.url(for:)`, `HostEndpoint.swift:86-89`). The plan extends it to `/v2/`, and no R1 test checks that refusal. `LisaAPIClient.send` is internal and checks the 1.x `Lisa-API-Version`, so the v2 client builds its own requests and credentials.
      - **Harness pattern:** R1's loopback helpers (`LoopbackAPIServer`, `TestHost`, `SyntheticCompanion`) are test-only. A harness opens `LisaHost.open(settings:platform:)`, starts the server, pairs in process (`createPairingCode`, `pairDevice`), and calls the device listener over loopback HTTP.
   5. **M3-5, in progress:** enrollment, the roster, revocation, key and credential lifecycle, challenges (§8.1); S-04, S-05. (Done outside the span order: D-61, as M3-D61.)
      - **Done, M3-5a** (`docs/VERIFICATION-SCENARIOS.md` M3-5a; D-62; SYNC-PROTOCOL §8f): Core's enrollment records, device registry, signed roster and revocation (schema v6, `CoreTrust`); `POST /v2/enrollments`, `GET /v2/trust/tls-anchors` and `GET /v2/trust`; the device's enrollment with its pending item, verified completion in the replica, `resume()`, and roster acceptance. Harness v10, 8/8.
      - **Done, M3-5b** (`docs/VERIFICATION-SCENARIOS.md` M3-5b): S-04 and S-05's TLS cases against R1's real TLS server, through the test-only libcurl pinning transport (`m3/harness-v14/`, a C shim plus `CurlPinAPITransport`, reusable by later harnesses), with certificates made at run time by the openssl CLI. Both modes, the three `ca` chain shapes, every pre-POST refusal with zero POSTs and no token bytes, TLS pin rotation with a peer's roster, and a lost answer replayed in both modes. Harness v14, 5/5.
      - **Done, M3-5c** (`docs/VERIFICATION-SCENARIOS.md` M3-5c; SYNC-PROTOCOL §8g): credential reset (the owner's one-time token, a new verifier signed by the existing key, the old credential refused) and challenges (the plan's message, monotonic expiry, run generation, single use, purpose, epoch and body binding, revocation mid-exchange, an unknown key). The harness found that revocation spent open challenges; fixed in `48a4e01`. Harness v15, 10/10.
      - **Done, M3-5d's first items** (`docs/VERIFICATION-SCENARIOS.md` "M3-5d, first items"): an expired certificate refused at first contact in both modes and by an enrolled device, and roster renewal. Harness v16, 6/6.
      - **Done, M3-5d's export-key rotation** (`docs/VERIFICATION-SCENARIOS.md`; `CoreExportKeys`): the roster announces the new key, and an old archive still opens with the retired key. Harness v19, 13/13.
      - **Done, M3-5d's signing-key rotation** (`docs/VERIFICATION-SCENARIOS.md`; D-65; SYNC-PROTOCOL §8h): dual-signed transitions activating at the next commit position, Core's history (schema v7), opening only with the current key, `importKeyTransition`, the devices' history with receipts verified by position, `GET /v2/trust` with the transitions. Harness v20, 15/15.
      - **Done, M3-5d's device key rotation** (D-66; SYNC-PROTOCOL §8i): `POST /v2/devices/current/key-update`, the roster's `previousKeys` (schema v8), re-signing pending work, and historical keys for committed operations, which also fixes a revoked device's committed history on replicas. Harness v22, 16/16.
      - **Left in M3-5:** re-anchoring after the signing key is lost (with M3-7's restore, S-10), and Design B certificates (only if N-1 selects them).
      - **M3-4's leftovers are done:** capabilities negotiation (M3-4b, D-63) and the per-path body limit (M3-4c, D-64).
      - **Practice:** the newest harnesses are v22 (loopback, every M3-5 suite) and v16 (TLS). Regression package v14 (`m2/make-regressions-v14.py`, runner `m2/run-regressions-v15.sh`) adds LisaArchive to the products and runs no target when its build fails. v12's run was invalid: its build failed and its runner ran the targets against the previous build. Don't edit Swift sources while a regression runs, because v35 and v47 rebuild from the working tree at its end. Harnesses build in `m3/harness-scratch-m3-5` (the project volume has 28 GB free). Regressions run with `m2/run-regressions-v9.sh` (package v8; scratch on the root volume). Harness v11 and v8 were corrected before their first builds, and v9 and v13 failed to compile; all four are kept unchanged.
   6. **M3-6, next:** `LisaLegacyRequests` and the v1 translation (§8.12.2); S-01 (with M3-0's fixtures), S-03. §8.12.2 has been read in full (2026-11-25T11:50Z). The slices:
      - **M3-6a, in progress:**
        - **Done:** the legacy origin with its derived incarnation and sequence (D-67), `LegacyChildSet` (children as a pure function of the request; `docs/SYNC-PROTOCOL.md` §8j) and Core's conversion frame (schema v9, `CoreLedger.legacyConvert`, `LegacyTransaction.intake`). Harness v26, 7/7.
        - **Step 3 begun (D-68):** the deferred projection, one R1 revision step per R1 call (harness v28's revision checks), and the projection-revision map (schema v10; harness v30, 8/8).
        - **Next, the exact action:** legacy edits' "observed at projection revision N" (§8.3.2 line 887, "Core maps N to the pieces observed at that revision when it decides the child").
          - **The finding:** without it, edits are `accepted_with_conflict` (harness v29's diagnostic).
          - **The design** (§8.3.2 read at 12:10Z; line 887 names v1 notes edits; §8.12.2's revision check covers fields):
            - A child is decided only when R1's `expectedRevision` equals the current projection revision N, so the edit saw exactly the state up to P(N), the position revision N reflects.
            - **The body** carries N in its `ObservedSet` (`projectionRevision`, **done**: `b6abecb`, `47f32cf`; harness v31, 9/9), so it stays a pure function of the request.
            - **At decision, done** (D-69; `1a8436e` to `6b3ec91`; harness v33, 15/15): Core resolves N through `core_projection_revisions` (schema v11 adds each revision's epoch) to the horizon `(epoch, "tasks", P(N))`, keeps it with the operation (`core_operations.observed_epoch` and `observed_position`), and folds with it in `CoreTaskFold.view`. `LegacyChange.observedRevision` puts N in the child. An unmapped N observes nothing.
            - **For replicas, done (2026-11-26; `53e2a5a`–`89fcb1a`; harness v34, 20/20; regression v19; `docs/VERIFICATION-SCENARIOS.md`, "observed horizons on replicas"):** Core serves the resolved horizon in Core-signed data, and replicas keep it with the canonical operation and fold with it, since they don't hold the map. "Decisions are made per epoch" (§8.12.2). The steps were: another epoch may resolve the same bytes differently. The steps:
              1. **surveyed (12:23Z):**
                 - `ChangeEntry` (`Sources/LisaSyncProtocol/ChangeEntry.swift:7`) has `position`, `partitions` and `change`, which is `.operation(SignedOperation, Decision)` or `.record(DerivedRecord)`.
                 - Change pages and full-snapshot chunks both carry it (`ChangePage.swift:74`, `SnapshotChunk.swift:52`), so one field covers both paths.
                 - Core builds entries in `CoreLedger.swift:~398-405` (the change-page builder) and `CoreSnapshots.swift:43`, from `core_change_log` joined to `core_operations`; both must select `observed_epoch` and `observed_position`.
                 - The replica keeps operations in `canonical_operations` (`Sources/LisaReplicaStore/ReplicaSchema.swift:171-183`, inserted at `CanonicalTables.swift:89`) and folds at `ReplicaStore.swift:933`.
              2. add an optional `observedHorizon` to `ChangeEntry`'s operation change, encoded only when present, so other entries' bytes don't change. The page's signature covers it;
              3. add a replica column, and use it in the replica's fold exactly as `CoreTaskFold.view` does;
              4. test it end to end: a legacy edit at Core, a replica pulling the page, and the same `TaskView` on both. Repeat it with a snapshot install.
          - **The router hook and `POST /v1/tasks`, done (2026-11-26; D-71; `f4879b6`–`12bd3fb`; harness v36, 7/7; regression v20).**
          - **`PATCH /v1/tasks/{id}`, done (2026-11-26; D-72; `ae0c52d`–`6cc8073`; harness v38, 15/15; `docs/VERIFICATION-SCENARIOS.md`).** It was built from the design below, with two corrections found by its harness: R1-only writes record their revision, and a status-only PATCH with no child still runs R1's transition.
            - **The design** (written 2026-11-26 at about 01:58Z, for D-72):
              - **The conversion:** inside the parent, in R1's order: the body size; the decode (400); the record (404 "the task"); the revision check (409 "the task changed since it was read", `currentRevision`); the correction, its deadline parsed (400); `TaskService`'s checks (403, 400). Nothing is committed before them.
              - **Field children:** one per field the request carries, with discriminators named after R1's fields: `field:title`, `field:notes`, `field:priority`, `field:deadline` (also for `clearDeadline`), `field:estimatedMinutes`, `field:confirmation`. Each is observed at N. They are taken in without projecting and projected once with `forceRevision` (R1's `correct` always writes), with a hint that marks `deadline` owner-corrected whenever the request sets or clears it, as R1 does.
              - **Then:** the `task.corrected` audit and `.taskChanged(material:)`.
              - **The status child, decided by the target alone, so the set stays a pure function of the request:**
                - `completed` → `task.complete`; `cancelled` → `task.cancel`;
                - `open` → `task.reopen` with no named actions, observed at N;
                - `inProgress` and `blocked`: no child. They are R1-only substates of an open task, which the projection already keeps, and the converter writes them to R1's record with R1's transition.
                - R1's transition rules decide the child against the record after the correction. A refusal (409 "the task cannot move from …") records `refused` and the answer, with the field children committed.
                - A status equal to the current one writes no audit, as R1 does.
              - **Protocol and merge changes:**
                - `note.replaceObserved` may have empty text, which removes the observed notes and adds none (R1's `notes: ""`).
                - `task.reopen` may name no action, and then reopens the terminal actions its observed coverage covers. `TerminalActions` keeps commit positions, so a horizon can cover them.
              - **The terminal replies for PATCH:** 200 with the current `TaskDTO` and `Lisa-Reply: current`; 404 "This change was applied; the task was deleted afterwards."
              - **The harness:** v37, differential against R1's path, as v36.
            - **Plan §8.12.2's route table** (re-read 2026-11-26, about 01:39Z):
            - **`POST /v1/tasks`:** one create-task child, the task ID derived from the parent; 201 `TaskDTO`, recorded atomically.
            - **`PATCH /v1/tasks/{id}`:** the revision check (409 "the task changed since it was read"), then every correction field validated together (400, nothing committed), then the field children, then the status child. A refused status (409 "the task cannot move from …") leaves the field children committed, with the error recorded.
            - **Replays:** the same key and fingerprint get the recorded response with `Lisa-Replayed: true`; a different fingerprint gets 422 `requestIDReused`.
            - **Later slices:** terminal replies and the reply dependency index (M3-6d).
        - **Surveyed facts for step 3 (2026-11-25T12:00Z):**
          - **R1's idempotency:** `APIRouter.idempotent` (`Sources/LisaAPI/APIRouter.swift:108-150`) keys `caller.scope:requestID`, with the fingerprint SHA-256 over `METHOD path\n`, the sorted `key=value\n` query lines and the body.
          - **The seam:** the plan links LisaLegacyRequests from LisaAPI (§7.2.1), so the router calls the converter there for converted routes. `DTOMapping` is internal to LisaAPI, so the router passes renderers (a `LisaTask` to its JSON, an error to R1's body) into the conversion, which runs them inside the transaction.
          - **The semantics to reproduce** are R1's `TaskService` (`Sources/LisaOwnerData/TaskService.swift`):
            - the principal is the owner or a paired device;
            - titles are trimmed and 1–200 characters; minutes are 1–1440;
            - the revision check answers 409 (`StoreError.conflict`), and the handler builds the 409 "the task changed since it was read" with `currentRevision` first;
            - a correction marks each changed field owner-corrected and keeps notes plain; a deadline set or cleared resets `unresolvedDeadlineText`; a material change (priority, deadline, confirmation) raises `changeSequence`;
            - audits are `task.created`, `task.corrected` and `task.<status>`; the transition is `LisaTask.transition(to:at:)`, marking status owner-corrected for extracted tasks;
            - creation sets confirmation `confirmed` and origin `manual`.
          - **Revisions:** R1 raises the revision once per service call, one for a correction and one for a status change. So the projection of a PATCH's field children must count as one step, and the status child as another (§8.12.2 "Projection revisions").
            - **The cause:** `TaskProjection.project` runs once per child (`CoreLedger.swift:279`), and R1's `records.update` raises the revision each time. R1 also raises it for a correction that changes no value, because `correct` always updates when any field is given, while the projection skips an update that changes nothing.
            - **The plan for it:** let `LegacyTransaction.intake` defer the projection, then add an explicit `project(entity:forceRevision:)` step. The converter takes the field children in, projects once (forcing the step when R1 would), then takes the status child in, which projects itself.
          - **Mapping:** R2's `TaskFieldValue` has title, priority, deadline, estimate, splittable and confirmation; notes are their own operation family.
      - **Gap noted (2026-11-26):** `PATCH /v1/ideas/{id}` shares the task PATCH's shape in §8.12.2, but R2 has no idea payloads, merge or projection yet. `OperationCatalog` names only `idea.create`, `idea.edit` and `idea.lifecycle`. It belongs with captures (M3-6c), which create ideas.
      - **M3-6b, the next slice. The design for its first step** (2026-11-26T02:17Z, for D-73):
        - **The entity:** a preference is a register per key, not an owner item.
          - Its ID is the first 16 bytes of `SHA-256("lisa-preference-key-v1" ‖ 0x00 ‖ key)`, so every device, Core and epoch agree, and R1's random record IDs don't matter.
          - Partition `preferences`.
        - **Payloads:**
          - `preference.set {key, value}`. The value is `{"kind":"text","text"}`, `{"kind":"number","number":"<decimal>"}`, `{"kind":"flag","flag"}` or `{"kind":"list","list":[…]}`. A number is a decimal string, because canonical JSON is integer-only; it is finite and in its shortest round-trip form.
          - `preference.delete {key}` and `preference.confirm {key}`.
          - A key is a token of 1–128 bytes. Whether a key and value are supported is checked at Core, with R1's rules.
        - **The merge:** `MultiValueRegister<value?>`, where a delete writes no value and replaces what it observed.
          - So a later set re-creates the key, as R1's delete-then-set does. §8.3.1's dominating tombstone is for owner items, which a key isn't.
          - A confirmation marks the model-authority candidates it observed as confirmed.
          - The key is absent only when every survivor is a delete. Otherwise the projection shows the first surviving value in display order.
        - **Step 1 done** (2026-11-26; D-73; `95d3e55`–`fc1c17f`; harness v41, 7/7): the payloads, the entity and the merge as designed.
        - **Step 2 done** (2026-11-26; `f404e2c`–`44cb3ed`; harness v43, 5/5). The questions about restricted keys move to step 3.
        - **Step 3a done** (2026-11-26; D-74; `aa0ec19`–`8313d30`; harness v45, 10/10; regression v26). What changed from the design below:
          - **Restricted keys** take the narrower reading of §8.17's "permitted": every administrative key, not only the model settings, plus unsupported keys.
          - **A blind change also observes something:** every converted preference child observes R1's record as Core found it.
          - **Core refuses a device's operation** on an administrative or unsupported key, or with an invalid value (R2-TRUST-05). Step 2 had accepted them.
        - **Step 3b-i done** (2026-11-26; D-75; `9b09007`–`e920b58`, then `40ec2d7`–`1621ecb`):
          - Holds in owner scope: the waiting parent, schema v12, decision keys and `LR-` tokens, `legacyHolds()`, and the unrecorded 503 with `Retry-After`.
          - R1's request and answer bytes now live in `LegacyPreferenceAnswers`, for the router and `resolve` alike.
          - Evidence: harness v47 12/12, then v48; the suite; regressions v27 and v28.
        - **Now, the exact next action, step 3b-ii:** `resolve`, the refusal guard, then the CLI.
          - **The frame,** `CoreLedger.legacyResolve(token:action:actor:decide:)` in one write transaction:
            1. **Parse:** `LegacyDecisionToken.typedPrefix`. Anything else is refused as not a decision token.
            2. **Match** every hold whose `token` starts with the prefix, waiting or decided. None: "LR-… doesn't name a waiting change." Two or more: refused, naming each match's scope, request ID and a longer token.
            3. **A decided match replays:** the same action returns the recorded outcome. Another action gets "Already decided: <action> by LR-… at <time>; nothing changed."
            4. **A waiting match** must be its parent's latest generation, with the parent `awaiting_administrative_review`. Otherwise it is refused, naming the waiting change and its token.
            5. **Decide:** the route's closure gets a `LegacyTransaction` and the hold's context: scope, request ID, fingerprint, the kept body, the held index and the generation.
            6. **What the frame writes:** the dispositions it returns (`UPDATE core_legacy_children`); the decision record on the hold row (a random decision ID, action, actor, time, outcome text); a new hold at generation + 1 if it reaches one; and on completion the parent `complete`, with status, body, expiry and `completed_at`, and `request_body` cleared.
          - **The route's side,** `LegacyPreferenceRoutes.resolve`:
            - It re-reads the kept body through `requested`. The children are a pure function of the request, so the plan is rebuilt with the same IDs.
            - **apply:** R1's state-dependent checks run again for the held change: the revision for a set, the record for a confirm or delete. A refusal now is R1's 409 or 404 template. Then the change is taken in, projected and audited, and the suffix is decided by the same loop as `update`, factored out of it, up to the next administrative key or the end.
            - **refuse:** the held child is `refused`, the rest `not_reached`. The answer is R1's 403 shape, `forbidden`: "This setting can be changed only on the administrative terminal."
          - **The refusal guard** (§8.14.8), schema v13: `core_legacy_refusal_guards(scope, request_id, fingerprint, status, body, created_at)`. It is content-free and never expires. The lookup consults it before a parent's body expiry, so the 403 replays for the dataset's life.
          - **"With the authority of that decision":** record the decision ID with the applied child, on Core's legacy child row or the hold's record. A receipt field would change the receipt format, so it is open until decided (D-76).
          - **Then the CLI:** `lisa core legacy review` and `resolve`. First read how a CLI process opens Core's ledger with its signing key: `LisaHost` doesn't open one yet, and M3-5d's key custody isn't wired to the host.
          - **Tests (S-03):** changes 3 and 5 of 7 administrative; resolve `LR-a` apply, with its reply lost and the command run again after a reopen of the store; `LR-a refuse` answering "Already decided"; a mistyped token; `LR-b apply` to the end, with the recorded full list; then the refuse run, with R1's 403 recorded, 6 and 7 `not_reached`, and the guard replaying after the body's expiry.
        - **Then, step 3c:** restricted siblings.
          - Children on restricted keys are taken in at Core but never served.
          - Only a Core-signed redacted receipt `{childID, index, disposition, commitPosition, opaqueCommitment}` replicates, with the 32-byte salt kept at Core. Its partition or record kind needs a decision.
          - The test: `model.endpoint` with a canary URL between two permitted keys, and the relayed bytes searched for the canary.
        - **Step 3 as designed** (2026-11-26, about 02:31Z), for the record:
          - **R1's semantics** (read 2026-11-26, about 02:31Z):
            - `SettingsHandlers.updatePreferences`: 1–50 changes, or 400 "send between 1 and 50 changes". Each change in order is a `set` (a value), a `confirm` (`confirm: true`) or a delete (neither). The first error stops the request, and the success body is the full preference list.
            - `PreferenceService.set`: model and runtime principals are refused; a paired device gets 403 for a consequential key; then `validate`. A record is found by key. `expectedRevision` is checked only when it exists, else inserted. It writes value, `explicit`, confirmed and `updatedAt`, always as one revision step, then the `preference.set` audit (detail `consequential` or `ordinary`).
            - `confirm`: only the owner or a paired device; 404 for an absent key; then `confirmed`, `updatedAt` and one revision step, with the `preference.confirmed` audit.
            - Delete (`DeletionService`): 404 for an absent key; 403 for a consequential key unless the owner. The plan adds that a device gets 403 for any delete.
          - **The design, recorded as D-74:**
            - **Administrative keys:** R2-TRUST-05's administrative keys are R1's consequential keys (`PreferenceKey.consequential`).
            - **Children:** `change:<index>` (set, confirm or delete), each observed at the change's `expectedRevision` if it has one.
            - **Projection:** `LegacyTransaction` gets a per-entity preference projection with `force`, as R1's set and confirm always write, plus R1's audits.
            - **Errors** come from templates that name positions (§8.12.2), e.g. "changes[3].key is not a supported preference".
            - **Owner scope:** an administrative key holds the request (hold generations, decision tokens, `legacy review` and `resolve`, the 503).
            - **Device scope:** an administrative key is refused at once (403), and the later children are `not_reached`.
            - **Restricted siblings:** `model.endpoint`, `model.dataSharing` and unsupported keys are never replicated; only redacted receipts replicate.
          - **The split:** 3a covers device scope and owner scope without administrative keys, with a differential harness against R1. 3b covers holds, tokens, the CLI and restricted siblings (S-03).
          - **Supported operations:** `CoreLedger.isSupported` and `checkPayload` accept `preference.*` on entity type `preference`. `checkPayload` decodes `PreferenceOperationPayload` and requires `entityID == PreferenceEntity.id(forKey:)`.
          - **`apply`:** it branches by entity type into a `CorePreferenceFold`, modeled on `CoreTaskFold` with resolved horizons. `PreferenceView.isConflict` gives `accepted_with_conflict`. The change log uses partition `preferences`.
          - **The projection** (`PreferenceProjection`) writes R1's `Preference` record: insert, update or delete by key, with origin `explicit` for owner authority and `confirmed` from the view.
            - It takes a `force` for R1's always-writing `set` and `confirm`.
            - It records the revision with `TaskProjection.recordRevision`, which works for any entity.
            - The value maps as text, number via `Double` and back, flag and list.
          - **The replica's fold** for preferences comes the same way, so Core's and a replica's view match.
          - **Restricted keys** (`model.endpoint`, `model.dataSharing`, "Core's model settings", §8.17): never served in change pages. Decide whether to keep them out of the `preferences` partition or refuse their device operations, before or with step 3.
        - **Step 3:** the conversion (`change:<index>` children, R1's stop at the first refusal, holds, `review` and `resolve`, restricted siblings).
      - **M3-6b's whole scope:**
        - **The scope:** the preferences PATCH, its same-key chains, administrative holds with hold generations and collision-safe decision tokens, `legacy review` and `resolve` (S-03).
        - **The model it needs first:** preference operations (set, confirm and delete per key) with a per-key merge and the projection into R1's preference records; restricted siblings with redacted receipts (§8.12.2); error templates without caller text.
        - **R1's semantics to keep** (`PreferenceService`, `SettingsHandlers.updatePreferences`):
          - 1–50 changes, in order, stopping at the first refusal;
          - `set` checks `expectedRevision` only when the key exists, so it inserts an absent key;
          - `confirm` on an absent key is a 404;
          - consequential keys are owner-only, and devices get 403 for them and for any delete;
          - the success body lists every preference.
      - **M3-6c:** captures with R1's permanent deduplication, notification receipts with R1's durable prefix, reminder, notification, proposal and plan-block actions.
      - **M3-6d:** terminal replies (the four cases), the reply dependency index, error templates without caller text, outcome-only migrated parents, and `upgrade_required` on v1.
      - **M3-6e:** S-01 against the frozen R1 client, queue and CLI from `491c90a` (M3-0's fixtures and `m0/frozen-client/harness4`).
   7. **M3-7:** backups, the recovery ledger, restore, fencing and admission (§8.4.4, §8.4.5, §8.5); S-09, S-10, §19.1.
   8. **M3-8:** `LisaFiringIdentity`, holds, the deterministic `Message-ID`, the Core side of ownership (§8.10); S-11 a–k.
   9. **M3-9:** `volume.json`, `identity --files` and `--offline`, host wrappers, the verification image and Compose inputs, `lisa core` (§8.11, §8.12.3); S-20.
   10. **M3-10:** zone generations and re-expansion (S-08 Core), the resolution finalizer (S-07 Core), the authority path (§8.3.5); S-16 HTTP.
   11. **M3-11:** `Apps/Probe` (syntax-checked), the X2 runner, then the M3 boundary with the R1 suite in debug and release. X2 is handed to the owner.
2. **Owner decisions open** (§5):
   - the run directory's build output, or a larger volume: 2.2 GB were free after the M2 boundary, and M3 needs room;
   - reopening the replica at 0 bytes free.
3. **While the owner runs X1:** import and evaluate the redacted results the owner shares; a nearby design is selected only from a passed proof (N-1), and M6 waits for it.
4. The deferred frozen fixtures before S-01 (M3) and S-02/S-13 (M9).
