<!-- R2 scenario records (plan §10.2, §8.18; O-6): for every scenario and baseline check, its commands, inputs, tool versions, hashes, expected outcomes and the evidence location of each run. A result is recorded only when a run produced it. -->
# Lisa R2 — Verification scenarios

**Rules.** Each record names its commands, inputs, versions, hashes, expected outcome and evidence location. A result appears only after a run produced it; everything else is "not run". Evidence lives in a fresh run directory `.tmp/r2/<run-id>/`. It is temporary and ignored by Git, and in the current Docker sandbox it exists only inside the VM; §4 says how the owner can collect a redacted copy. Statuses, executors and causes follow plan §10.1.

## 1. Platform of the runs recorded here

| Item | Version |
|---|---|
| Host | Docker Sandboxes VM `lisa.lab`: Debian 13 (trixie), x86_64, kernel 7.0.14, 24 CPUs. Labeled "Debian 13 sandbox"; never Fedora (owner decision, 2026-11-24; `DEVELOPMENT-ENVIRONMENT-REPORT.md` §13) |
| Swift | 6.4.2 (`swift-6.4.2-RELEASE`, primary) at `/opt/swift/swift-6.4.2-RELEASE-debian13`; 6.4.3 (`swift-6.4.3-RELEASE`, comparison) at `/opt/swift/swift-6.4.3-RELEASE-debian13` |
| SQLite | 3.46.1 (`libsqlite3-0` 3.46.1-7+deb13u2+dhi4) |
| OpenSSL | 3.5.9 |
| libxml2, libcurl | 2.9.14 (`libxml2` 2.12.7+dfsg+really2.9.14-2.1+deb13u3+dhi3); 8.14.1 (`libcurl4t64` 8.14.1-2+deb13u7+dhi1) |
| Container engine | Docker 29.10.0, rootful, inside the VM; Compose 5.8.0; Buildx 0.39.1. Not used by M0 |
| Lockfile | `Package.resolved` SHA-256 `9608e8e024c6cbe0ea3fc269c5d80dcba8235c585f852de0e0c046a1dab37494` |

## 2. M0 baseline (run `20261124-r2-5462`)

### M0-1 The unmodified R1 suite (O-5; R2-L01 first run, R2-L02 baseline)

- **Inputs:** the working tree at `051d9d4`, whose `Sources/`, `Tests/`, `Fixtures/`, `Package.swift` and `Package.resolved` equal `491c90a` (`git diff --name-status 491c90a HEAD` lists only `DEVELOPMENT-ENVIRONMENT-REPORT.md` and `plans/R2.md`).
- **Commands** (R1's documented procedure, `docs/SETUP-LINUX.md` §4, from the project root, a fresh scratch path per toolchain): `swift build --scratch-path .build/r2-m0-20261124-r2-5462/swift-<version> -c <debug|release> --build-tests`, then `<scratch>/out/Products/<Debug|Release>-linux-x86_64/LisaTests-test-runner --testing-library swift-testing`. Script: `.tmp/r2/20261124-r2-5462/m0/run-suite.sh`.
- **Expected:** builds succeed; every test passes; failures, if any, recorded as they are and classified (§10.3).

| Toolchain, configuration | Started (UTC) | Build | Test runner SHA-256 | Result |
|---|---|---|---|---|
| 6.4.2 debug | 2026-11-24T07:54:37Z | exit 0, 37.7 s wall, 0 warnings | `9240fefdebebf657aad234169cad14ec6d0df799f688383fc480ba8899969f83` | **PASS**: 376 tests in 66 suites, exit 0 |
| 6.4.2 release | 07:55:18Z | exit 0, 113.5 s, 0 warnings | `a13a5f4d4f9b2fdf9786e6658c440c6e494043d33879845b38007d4368d4d6d0` | **PASS**: 376 in 66, exit 0 |
| 6.4.3 debug | 07:57:14Z | exit 0, 34.1 s, 0 warnings | `a67c3607dad2b249977f39f0fe14b4c664980f2efd7588653db9408d0a347ed9` | **PASS**: 376 in 66, exit 0 |
| 6.4.3 release | 07:57:52Z | exit 0, 112.0 s, 0 warnings | `bb163890615a25ee8b851e28d2400791740b305cff989e5048f2f948fcca820a` | **PASS**: 376 in 66, exit 0 |

Compiler paths: `/opt/swift/swift-<version>-RELEASE-debian13/usr/bin/swift-driver`. `Package.resolved` had the same hash before and after every build. Evidence: `.tmp/r2/20261124-r2-5462/m0/suite/<version>-<configuration>/` (`env.txt`, `build.log`, `runner.txt`, `test.log`, exit files). Executor: Claude; unit, integration, recovery, acceptance and adapter tests against loopback controlled servers, no live service.

### M0-2 The offline demo

- **Command:** `<scratch>/out/Products/<Debug|Release>-linux-x86_64/lisa demo --data-dir <evidence>/demo-data --json`, after each build above.
- **Expected:** exit 0 and every check passing.
- **Result: PASS** for all four builds: 8 steps, 30 of 30 checks. `lisa` SHA-256: 6.4.2 debug `552d05ca0a066ce3006697b99dc566dcac50cfe84acda9bffbe1971a13dd6084`, 6.4.2 release `53a1a79272dfd5eae2984b4029d4d4a0016b08bd23c60ea722f5c500a19cf781`, 6.4.3 debug `94e052d420bca9128197fadc83d88d8dd6a872699968282566f37801b881b0e3`, 6.4.3 release `f54aface43d065845e36113bcb090f246a2f1c6a05a66a8a8043029dd105235e`. Evidence: `demo.json` in each run directory above.

### M0-3 Frozen R1 sources (§8.18 step 1)

- **Command:** `.tmp/r2/20261124-r2-5462/m0/reconstruct-r1.py`: walk `git show --no-textconv 491c90a:<dir>/` from the root and write each blob from `git show --no-textconv 491c90a:<path>` into `m0/r1-src/` (permitted Git use; no archive, no checkout).
- **Check:** for every file, SHA-1 of `"blob <size>\0" + bytes` equals `git rev-parse 491c90a:<path>`.
- **Result: PASS.** 872 files, each byte-exact. The manifest `m0/r1-src.manifest.tsv` lists path, size, Git blob ID and SHA-256 per file; the SHA-256 of its data rows is `5e0524fccc331522b17cbf8439cb7043830522d1ea0f4b3b5764f4aa99b46679`. In the tree: `Package.swift` `3823487b8d83beb7bd97e5c973d4e5ba1c5f818e143ddb7367c7cddee2198b44`, `Package.resolved` `9608e8e0…a37494`.
- **Reproduction:** the same script against the same commit reproduces the same manifest hash.

### M0-4 Frozen R1 binaries (§8.18 step 2)

- **Commands:** in `m0/r1-src/`, with Swift 6.4.2 (the owner's baseline replacing the plan's 6.3.2): `swift build -c debug`, `swift build -c release`. Script: `m0/build-frozen-r1.sh`.
- **Result: PASS.** Exit 0 both (28.8 s and 49.1 s wall, warm package cache). `lisa` debug `220690d1a99ec8256d8a98772938a460b96404da109b864c36ef03a4b2664f0b`, release `34ef4335e8590b581e9f302c6f1a6600e433d8b3a0115268e34f763296b69bff`, at `m0/r1-src/.build/out/Products/<Debug|Release>-linux-x86_64/lisa`. These hashes identify these builds; the binaries embed their build paths, so a rebuild elsewhere has its own hashes, and the source manifest of M0-3 is the reproducible identity.
- **R1 Apple build:** not here. The owner builds the R1 Mac app from the same reconstructed tree at or before X3 (E-12).

### M0-5 Frozen-client harness and R1 queue files (§8.18 steps 2–3)

Not recorded yet: in progress in `m0/frozen-client/`.

### M0-6 Frozen R1 datasets (§8.18 step 3)

Not recorded yet: in progress in `m0/frozen-datasets/`.

## 3. Scenario index (plan §10.2)

Not run unless a row says otherwise. Each scenario's full content is in plan §10.2; its records join this file when its milestone runs it.

| ID | Subject | Milestones and sessions | Status |
|---|---|---|---|
| S-01 | v1 translation with the frozen R1 client, queue and CLI | M3 | Not run |
| S-02 | R1 queue classification and post-downgrade reconciliation | M9 | Not run |
| S-03 | The one legacy converter | M3, M9, X7 | Not run |
| S-04 | First-contact owner-text key in both TLS modes | M3, X2 | Not run |
| S-05 | Bounded device-only retry and the test-only enrollment-result fault | M3, X2 | Not run |
| S-06 | Snapshot installation under writes | M2 | Not run |
| S-07 | Pieces, value limits, reviewed-set artifacts | M2, M3, M5 | Not run |
| S-08 | Interval coverage and the planning-zone change | M2, M3, M6 | Not run |
| S-09 | Backup lineage, anchors and discovery | M3 | Not run |
| S-10 | Re-anchoring, restore, fences and admission | M3 | Not run |
| S-11 | Delivery holds after a restore; (l) recorded against KF-1 | M3, M4, M8 | Not run |
| S-12 | Reminder firings and OS ownership; (m) recorded against KF-2 | M8, X6 | Not run |
| S-13 | Export, rollback and installation of either v4 database | M5, M9, X3, X7 | Not run |
| S-14 | The destination policy at every redirect | M7, X1, X5 | Not run |
| S-15 | VPN publishing | M4, target host | Not run |
| S-16 | Size boundaries and bounded dependency release | M1, M3, M6 | Not run |
| S-17 | SQLite readers, exhaustion and bursts | M2, M3 | Not run |
| S-18 | Model accounting | M7 | Not run |
| S-19 | Deletion and expiry propagation | M5, M8 | Not run |
| S-20 | Health, CLI modes and the deployment wrappers | M3, M4 | Not run |
| S-21 | Mail and calendar connectors against controlled servers | M7 | Not run |
| S-22 | Model adapters and the controlled local Ollama server | M7 | Not run |
| S-23 | Outbound email and calls against controlled servers | M8 | Not run |
| S-24 | The owner-verification harness itself | M1, then every milestone | Not run |
| N-A | Narrative §19.1 | M3, M4, M8 | Not run |
| N-B | Narrative §19.2 | M9, X7 | Not run |

## 4. Collecting evidence outside the VM

Run directories exist only in this sandbox. Tracked records like this file reach the host when the owner fetches the branch's commits. For the raw evidence, Claude builds a redacted bundle on request (or at each milestone): a `.tar.gz` with a SHA-256 manifest, after a scan that masks tokens, account identifiers and e-mail addresses. The owner copies it out through a port the owner publishes; the exact command is in `R2-CHECKPOINT.md`.
