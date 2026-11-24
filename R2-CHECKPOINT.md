<!-- Resumable R2 implementation record (R2-DEV-03; plan §14, O-7): branch and baseline, milestone, completed requirements, files, commands and results with evidence, blockers, pending owner sessions, permissions, the last buildable checkpoint, the quota guard and the next steps. -->
# Lisa R2 — Checkpoint

**Updated:** 2026-11-24T13:50Z by Claude, run `20261124-r2-5462`. **Milestone:** M0 — Baseline, complete at its boundary (two fixture groups are scheduled for M3 and M9, §5); **M1 — Contracts and Apple proofs, complete at its boundary** (a clean checkout of `d0a9e53` builds in debug and release with 0 warnings, the R1 suite passes 376/66, and the harness's fixture cases pass 9 of 9); **X1 is handed to the owner** (§6); M2 — Replication engine, next. Resumed at 12:53Z after the 09:45Z quota pause by the guard's first real launch (§9).

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
| SQLite WAL-reset fix | Before M2 and M3 durability results are accepted: the DHI image carries no Debian changelog, so either Debian's patch is verified from its published source, or every relevant writer and checkpoint is shown to be serialized (§13 of the environment report) |

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

`d0a9e53` (M1's last code commit; later commits change documents only): a clean reconstruction builds in debug with tests and in release with 0 warnings, the unmodified R1 suite passes 376 tests in 66 suites, and `lisa-verify`'s fixture cases pass 9 of 9 (Swift 6.4.2). Earlier checkpoints of this run: `9cca054` and `fae7ba1` (the harness), `559f4bb` (`Apps/Proof`), `c69586c` (the wire contracts), `505ee96` (`LisaArchive`), `13ce72c` (paging), `e7e5085` (envelope), `822ffe5` (`LisaTrust`), `2abce7e` (`LisaCrypto` additions), `4a8826b` (`LisaSyncProtocol`), and the swift-crypto span's `fd94a78`.

## 9. Quota monitoring, the guard, pause and resume

- **Readings.** `.tmp/r2/20261124-r2-5462/usage/usage_read.py` starts a headless Claude Code process that sends only the SDK `get_usage` control request (no prompt, no model call); Claude Code fetches `/api/oauth/usage` itself. A reading counts as fresh only if that fetch happened inside the process; values served from Claude Code's shared 60-second cache are refused. While Claude works, the status-line tap records the session's own rate-limit fields after every response. Logs: `usage/readings.jsonl`, `usage/statusline.jsonl`.
- **Proved on 2026-11-24:** a fresh reading during development (07:52:11Z, 0% used, reset 12:49:59.72Z, matching the status line) and a fresh reading by a detached process while Claude was idle after its turn ended (08:12:02Z, 6%; no transcript entry and no model request during the reading).
- **The guard.** `.tmp/r2/20261124-r2-5462/guard/guard.py`, one detached process, bound to this account (hash `0c503c8f4594e0fb`), session lineage, sandbox checkout and run ID. It waits without model calls for a recorded quota pause or a verified quota interruption, confirms the reset with a fresh reading after the reported reset plus 180 s, checks the other plan windows, and launches one writer (`resume-launcher.sh`: a forked resume of the session) under the repository writer lock. The interactive session holds that lock through a lease helper. Rehearsed with simulated readings, a short clock and a harmless launcher at 08:02Z and 08:08Z: 10 of 10 scenarios passed. The real launcher has not run yet; its first use will be the first post-reset resume.
- **Owner commands.** Inspect: `.tmp/r2/20261124-r2-5462/guard/guardctl status`. Stop: `guardctl stop --reason "<why>"` or `touch .tmp/r2/20261124-r2-5462/guard/live/STOP`. After a VM restart nothing restarts by itself: run `guardctl daemon --detach`, or resume Claude, which restarts it. A guard stopped by the owner restarts only with `--rearm "<reason>"`.
- **Pause procedure.** At 80–85% used: drain workers and shorten batches; be paused by about 90%, earlier if the burn rate or in-flight work could consume the reserve. Before pausing: account for running processes, update this file, write a new `.tmp/r2/20261124-r2-5462/pause-<UTC>-<unique>.md` (HEAD, unfinished work, evidence, owner checks, measured usage and reset, the exact next safe action), record it with `guard.py pause`, release the writer lease, end the turn.
- **Batch sizing.** Two concurrent agents plus this session used 11 points of the window in 4 minutes on 2026-11-24 (08:36–08:40Z). Agents now run one at a time unless usage is low, and a background watchdog that makes no model calls wakes this session at 70%.
- **Evidence for the owner.** `python3 .tmp/r2/20261124-r2-5462/export/make_bundle.py` writes a redacted `bundle-<UTC>.tar.gz` with its SHA-256 (it refuses to package if a canary survives). To copy one out: publish a port once on the host (`sbx port publish lisa.lab 8765:8765`), ask Claude to run `export/serve-bundle.sh`, then `curl -fO http://localhost:8765/<bundle>.tar.gz`.
- **The first real resume (2026-11-24):** the guard recorded pause `P-20261124T094325Z-14b7b7` at 09:43Z, took a fresh reading at 12:53:00Z (0%, reset confirmed after 12:49:59Z plus the 180 s buffer) and launched `L-3930e57701`, a forked headless resume of the session; it was acknowledged at 12:53:07Z by session `d0d5cdce-07e8-48a9-a66e-d38baa446cdf`, which is the writer since. Its fresh reading at 12:54:02Z showed 2%, next reset 17:49:59Z. A headless session runs no status line, so its readings come from `usage_read.py` alone.
- **Resume.** Only a recorded quota pause or a verified interruption is resumed, once a fresh reading confirms usable capacity and the previous writer released the lock. Resuming first inspects files and processes. A manual resume takes the lease with `--consume-pauses`, so the guard never launches a second writer.

## 10. Owner action ledger

No live action or external submission has been requested or performed in this run. **Owner check requested:** X1 (§6), on the owner's devices only; it involves no account, provider or real action, so the action ledger records none.

## 11. Next steps

1. **M2 — Replication engine** (plan §9): LisaMerge, LisaReplicaStore (membership records, deferred pages), LisaLocalSearch, the LisaSQLite and LisaTime additions, and the first container use (the rootful engine authorized on 2026-11-24, labeled as such). First, the SQLite WAL-reset check (§5) before any M2/M3 durability result is accepted. LisaTrust's roster, lineage and key-history verification and the receipts are built where they are first exercised (the replica at M2, Core at M3); the plan's M1 evidence list doesn't include them.
2. While the owner runs X1: import and evaluate the redacted results the owner shares; the nearby design is selected only from a passed proof (N-1), and M6 waits for it.
3. The deferred frozen fixtures before S-01 (M3) and S-02/S-13 (M9).
