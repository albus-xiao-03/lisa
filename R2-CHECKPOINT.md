<!-- Resumable R2 implementation record (R2-DEV-03; plan §14, O-7): branch and baseline, milestone, completed requirements, files, commands and results with evidence, blockers, pending owner sessions, permissions, the last buildable checkpoint, the quota guard and the next steps. -->
# Lisa R2 — Checkpoint

**Updated:** 2026-11-24T21:47Z by Claude, run `20261124-r2-5462`. **Milestone:** M0 complete; **M1 complete at its boundary** (X1 handed to the owner, §6); **M2 — Replication engine, in progress** (M2-0 to M2-9, §4). **Working:** resumed manually at 20:33Z after the VM restart (§5, §9); the second quota pause (13:58Z) was consumed by that resume. Fresh reading at 20:33:29Z: 2% used, reset 2026-11-25T01:20:00Z (20:20:00 EST).

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
- **Commits since the resume at 20:33Z:** the observed set's canonical form `ef9f546`; `LisaReplicaStore`'s first span `5ddd7d2` → `3ee84a0` (28 files); D-56 `528f236`; `Package.swift` `818fe3c`; `docs/VERIFICATION-SCENARIOS.md` M2-3 `742675f`; `4bb6f35` (this file); the reader monitor and capture path `5d9a9c6` → `0aac9d1` (`LisaSQLite` six files, `LisaReplicaStore` three); M2-4 `3455908`; `40ea1b7` (this file); the item payload schemas `57c50b0` → `75326ea` (LisaSyncProtocol, five files), `TaskMergeState` `f093e69` → `8e0e73b` (LisaMerge, three), the store's payload checks `4e0c1e3`; `docs/SYNC-PROTOCOL.md` `43b5369`; `docs/CONFLICTS.md` `fae2ba7`; M2-5 `446c87e`; `6d9f637` (this file); the effective view and persisted causal release `83791b1` → `09cf01a`; M2-6 `76c54e4`; `6af003f` (this file); `LisaLocalSearch` `8b5cb7e` → `cd37d4f` (with D-57 `703e64f`); M2-7 `358406a`; `fb68439` (this file); resolution groups and the advisory note limit `9c88032` → `3fb9b7f`; `docs/SYNC-PROTOCOL.md` `c606ac5`; M2-8 `9b10d32`; `9bfd698` (this file); the monotonic clock `6279859` → `437ca91` (LisaTime, four files); M2-9; then this file.
- **Temporary files:** only under `.tmp/r2/20261124-r2-5462/`: the M0 scripts and logs (`m0/`), the frozen R1 tree and its builds (`m0/r1-src/`), the usage monitor (`usage/`), the guard and its rehearsals (`guard/`), the recipe tests (`notes/`), the M1 harnesses v1–v5, the proof proposal and its checks, the S-24 runs and the clean-checkout matrix (`m1/`). None is committed; none is removed or overwritten.

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

The first outcomes passed, so M0 needed no production fix. Every run directory and log is new; first outcomes are kept as recorded.

## 5. Open conflicts, blockers and unavailable evidence

| Item | Status, executor and cause |
|---|---|
| Fedora 45 with Swift 6.3.2 (§4 C8, §8.18 step 2, P-08's toolchain list) | `NOT_RUN_ENVIRONMENT` (Claude; the platform changed; Swift 6.3 has no Debian 13 build). The owner set Swift 6.4.2 on Debian 13 as the baseline |
| E-5, libxml2 2.15 and OpenSSL 4.0 | `NOT_RUN_ENVIRONMENT` (Claude; Debian 13 ships libxml2 2.9.14 and OpenSSL 3.5.9) |
| Rootless engine evidence for G2: UID/GID mapping, secret access | `NOT_RUN_ENVIRONMENT` (Claude; this engine is rootful). Genuine rootless amd64 evidence is still required |
| arm64 | `NOT_RUN_ENVIRONMENT` (Claude; no arm64 environment); R1's historical results only |
| SELinux, VPN and off-VPN reachability over IPv4 and IPv6, D05 | The owner's, on the target host; pending M4 |
| Apple builds and devices (X1–X7), live providers (LS-1–LS-3) | The owner's sessions; pending their milestones |
| Proton Calendar | Provider capability blocker: no authenticated, private, read-only interface; G4 and G5 stay open (§8.19.6) |
| KF-1, KF-2 | Open, deferred by the owner on 2026-11-23, no waiver |
| Frozen fixtures not yet produced | A raw `sending` queue file left by a killed process and the pruning pair (due before S-01 at M3); `acceptedByProvider` (R1 trusts only the system store for SMTP, so a controlled server needs another route), `confirmedDelivered` and paired-device flows through `lisa serve`, `inProgress`, model-budget consumption, the capture-title and shared-URL cases, richer revision histories and plan-block actions (due before S-02 and S-13 at M9) |
| Reopening the replica at 0 bytes free | Observed in M2-4: it fails with "storage full" (opening records a new incarnation, and WAL mode needs room for its `-wal` and `-shm` files); every save stays intact and it opens once space returns. The plan releases the ballast only on the capture path. **For the owner:** whether the ballast may also be released to open the replica at launch; otherwise the app (M5) reports "Storage is full" without the replica and retries the open when space returns |
| SQLite WAL-reset fix | Settled by design (D-55, M2-0): the loaded library isn't shown to carry the fix, so every WAL database has one writer and checkpointer under an exclusive lock and read-only readers; the guard's checks pass. The production image's library is judged the same way at M4 |

**Environment event (2026-11-24, the VM stopped):** the sandbox VM stopped after 16:57:14Z (the guard's last heartbeat) and before 17:53Z, when the guard would have taken its post-reset reading; it booted again at 20:25:22Z. The guard and its pending pause `P-20261124T135657Z-39d87a` didn't run in between, so nothing launched. The owner resumed Claude in the original interactive session; Claude inspected the files and processes (HEAD `d31a943`, clean tree, no writer, 21 GB free, toolchains and Docker present), took a fresh reading, took the writer lease with `--consume-pauses` at 20:33:37Z and restarted the guard (pid 2746). Nothing was lost: the last commit before the stop was the pause checkpoint.

**Environment event (2026-11-24T13:47Z):** the project volume filled (49 GB, 5.6 MB free) and a link failed. The SwiftPM scratch outputs of superseded builds under `.build/` were removed (24 GB). They are ordinary build output, not temporary files (`CONSTRICTION.md`); their logs and runner hashes are kept in `.tmp/`, which wasn't touched. Routine builds now reuse `.build/r2-run`, and storage is checked before large builds.

**Process deviation, recorded (temporary files):** plan §10.2 says nothing in a run directory is overwritten. Until about 09:00Z this run edited temporary scripts in place while developing them: `usage/usage_read.py`, `usage/statusline_tap.py`, `guard/guard.py`, `guard/rehearse.py` and `m1/harness/Package.swift`. No log, reading, report or evidence file was overwritten, but the first guard rehearsal (`rehearsal-20261124T080243Z`) ran an earlier `guard.py` than the second (`rehearsal-20261124T080830Z`) and the live guard, which run the corrected one. Since then every revision of a temporary file is a new file (`harness-v2/`, `EnvelopeTestsV2`, `MerkleTestsV2`, `NOTES-2.md`).

**Process deviation, recorded:** before 08:08Z this run used five read-only Git commands outside the plan's allowed set (§3): `git worktree list`, `git merge-base --is-ancestor`, `git ls-files`, `git rev-list --max-parents=0` and `git symbolic-ref`. None changed anything. Each was replaced (by `rev-parse`, `log` or a `git show` walk), and only `status`, `diff`, `log`, `show`, `rev-parse`, `add` and `commit` are used since.

## 6. Pending owner sessions and experiments

**X1 is requested (2026-11-24T13:50Z):** entry point `Apps/Proof` (scheme `LisaProof`, test plan `X1`) with `swift run lisa-verify quickstart`; the sheet is `Harness/docs/SETUP-APPLE.md` (prerequisites, build and signing, roster, the nine nearby cells for both designs, the nine fetch-probe cases on each device, the three E-2 builds, expected observations, and the redacted export to return). Cases: `OV-NEAR-{MI,MP,IP}-01..03` (paired), `OV-APPLE-X1-01..03`, `OV-APPLE-X1-FETCH-01..09`. Still to come: X2 (after M3), X3 (after M5, with the R1 Mac build for X7), X4 (after M6), X5 and LS-1/LS-2 (after M7), X6 and LS-3 (after M8), X7 (at M9), target-host checks (from M4). None is requested yet; each gets its entry point, prerequisites, case IDs, expected observations and the redacted results to return when its milestone delivers it.

## 7. Permissions in force

- **Engine:** the rootful Docker daemon inside `lisa.lab` (owner, 2026-11-24; P-02, P-03, account-free P-09a at their milestones).
- **P-07:** any R1 test or test-support change needs the owner's approval of a request naming the file, reason and evidence.
- **Dependencies:** existing versions may change after the freeze when necessary or beneficial (swift-crypto 5.1.2 first, SwiftNIO 2.105.1 assessed), each with revisions, rationale, lockfile change and regression results. **P-08** stays conditional on N-1 and on the owner's approval of the exact swift-certificates pin. **P-09a:** Proton Mail Bridge 3.27.2 on amd64.
- **Kept by the owner:** the host, accounts, image publication, production deployment, real-data cutover, the Apple Developer account, every live provider action and every device session.

## 8. Last buildable checkpoint

`437ca91` (`LisaTime`'s monotonic clock): a full debug build with tests has 0 warnings and the unmodified R1 suite passes 376 tests in 66 suites (Swift 6.4.2); harnesses v13 (5), v15 (7), v19 (4), v20 (3), v21 (10), v25 (6) and v26 (3) pass. Before it, `3fb9b7f` (paged resolution groups), `cd37d4f` (`LisaLocalSearch`), `09cf01a` (the effective view and persisted causal release), `4e0c1e3` (the item payload schemas and `TaskMergeState`), `0aac9d1` (the reader monitor and the capture path, with the container cases), `818fe3c` (`LisaReplicaStore`'s first span), `386a738` (`CausalRelease`) and `c9fed41` (the WAL guard). `d0a9e53` is M1's clean-checkout checkpoint (debug and release, R1 suite, fixtures 9/9). Later commits change documents only.

## 9. Quota monitoring, the guard, pause and resume

- **Readings.** `.tmp/r2/20261124-r2-5462/usage/usage_read.py` starts a headless Claude Code process that sends only the SDK `get_usage` control request (no prompt, no model call); Claude Code fetches `/api/oauth/usage` itself. A reading counts as fresh only if that fetch happened inside the process; values served from Claude Code's shared 60-second cache are refused. While Claude works, the status-line tap records the session's own rate-limit fields after every response. Logs: `usage/readings.jsonl`, `usage/statusline.jsonl`.
- **Proved on 2026-11-24:** a fresh reading during development (07:52:11Z, 0% used, reset 12:49:59.72Z, matching the status line) and a fresh reading by a detached process while Claude was idle after its turn ended (08:12:02Z, 6%; no transcript entry and no model request during the reading).
- **The guard.** `.tmp/r2/20261124-r2-5462/guard/guard.py`, one detached process, bound to this account (hash `0c503c8f4594e0fb`), session lineage, sandbox checkout and run ID. It waits without model calls for a recorded quota pause or a verified quota interruption, confirms the reset with a fresh reading after the reported reset plus 180 s, checks the other plan windows, and launches one writer (`resume-launcher.sh`: a forked resume of the session) under the repository writer lock. The interactive session holds that lock through a lease helper. Rehearsed with simulated readings, a short clock and a harmless launcher at 08:02Z and 08:08Z: 10 of 10 scenarios passed. The real launcher has not run yet; its first use will be the first post-reset resume.
- **Owner commands.** Inspect: `.tmp/r2/20261124-r2-5462/guard/guardctl status`. Stop: `guardctl stop --reason "<why>"` or `touch .tmp/r2/20261124-r2-5462/guard/live/STOP`. After a VM restart nothing restarts by itself: run `guardctl daemon --detach`, or resume Claude, which restarts it. A guard stopped by the owner restarts only with `--rearm "<reason>"`.
- **Pause procedure.** At 80–85% used: drain workers and shorten batches; be paused by about 90%, earlier if the burn rate or in-flight work could consume the reserve. Before pausing: account for running processes, update this file, write a new `.tmp/r2/20261124-r2-5462/pause-<UTC>-<unique>.md` (HEAD, unfinished work, evidence, owner checks, measured usage and reset, the exact next safe action), record it with `guard.py pause`, release the writer lease, end the turn.
- **Batch sizing.** Two concurrent agents plus this session used 11 points of the window in 4 minutes on 2026-11-24 (08:36–08:40Z). Agents now run one at a time unless usage is low, and a background watchdog that makes no model calls wakes this session at 70%.
- **Evidence for the owner.** `python3 .tmp/r2/20261124-r2-5462/export/make_bundle.py` writes a redacted `bundle-<UTC>.tar.gz` with its SHA-256 (it refuses to package if a canary survives). To copy one out: publish a port once on the host (`sbx port publish lisa.lab 8765:8765`), ask Claude to run `export/serve-bundle.sh`, then `curl -fO http://localhost:8765/<bundle>.tar.gz`.
- **The first real resume (2026-11-24):** the guard recorded pause `P-20261124T094325Z-14b7b7` at 09:43Z, took a fresh reading at 12:53:00Z (0%, reset confirmed after 12:49:59Z plus the 180 s buffer) and launched `L-3930e57701`, a forked headless resume of the session; it was acknowledged at 12:53:07Z by session `d0d5cdce-07e8-48a9-a66e-d38baa446cdf`, which is the writer since. Its fresh reading at 12:54:02Z showed 2%, next reset 17:49:59Z. A headless session runs no status line, so its readings come from `usage_read.py` alone.
- **The third resume (2026-11-24T20:33Z, manual, after the VM restart):** fresh reading 20:33:29Z, 2% used, next reset 2026-11-25T01:20:00Z; lease `interactive:321` (holder pid 2737) consumed `P-20261124T135657Z-39d87a`; the guard restarted as pid 2746 with no pending pause. A new alarm, `usage/watchdog_v1.py` (reads the status-line log only, no model call), ends a background task at 70% so the session sees it.
- **Resume.** Only a recorded quota pause or a verified interruption is resumed, once a fresh reading confirms usable capacity and the previous writer released the lock. Resuming first inspects files and processes. A manual resume takes the lease with `--consume-pauses`, so the guard never launches a second writer.

## 10. Owner action ledger

No live action or external submission has been requested or performed in this run. **Owner check requested:** X1 (§6), on the owner's devices only; it involves no account, provider or real action, so the action ledger records none.

## 11. Next steps

1. **M2, next span: change pages, partition cursors and membership records** (§8.4.2, §8.4.3) on the replica: Core-signed pages verified and applied per partition with the four cursor cases, row versions, membership records and the absence rule, deferred pages during a repair, and the canonical pieces they carry entering the effective view (the page format is specified here and implemented by Core at M3). The other types' payload schemas follow, type by type.
2. **Then the rest of M2:**
   - signed change pages, partition cursors with the four page cases, membership records and the absence rule, deferred pages (§8.4.2, §8.4.3);
   - the staged snapshot installation (§8.6.3; S-06) with kills at each step, including storage filling during an installation and the peak staging, index and WAL sizes (S-17's last M2 parts);
   - the M2 boundary: debug and release, lint, a clean checkout, fixtures.
3. **While the owner runs X1:** import and evaluate the redacted results the owner shares; a nearby design is selected only from a passed proof (N-1), and M6 waits for it.
4. The deferred frozen fixtures before S-01 (M3) and S-02/S-13 (M9).
