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
| Lockfile | M0-1 to M0-6: `Package.resolved` SHA-256 `9608e8e024c6cbe0ea3fc269c5d80dcba8235c585f852de0e0c046a1dab37494` (R1's, kept by the frozen artifacts). From M0-7 on: `f846319595094d9399eccd89f565e571db298f5dab8c46543bcd7d95bc91e776` (swift-crypto 5.1.2, `docs/DECISIONS.md` D-53) |

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

- **Harness:** a temporary SwiftPM package, `m0/frozen-client/harness3/`, depending only on `../../r1-src` by path and linking R1's `LisaClient` and `LisaAPIContract`. Built with Swift 6.4.2 and `--force-resolved-versions`: debug and release exit 0, 0 warnings; `frozen-client-harness` debug `51a0b06f960d86f09224d5cde6524bc3b9f4b11ac30e3bf3e882081faaf707ae`, release `990e6e06b6ff4100581d11d5dd5988d6ebdf7aec3d95a4aef3a72b5f05efdb15`. Its lockfile stayed `9608e8e0…a37494`. Three earlier attempts that failed to build are kept beside it, unchanged (`COMMANDS.md` explains each).
- **Queue files:** 25 files in `m0/frozen-client/queues/`, each written by R1's own `OfflineQueue` and `FileQueueStorage` (release binary), driven by a scripted `APITransport` or, where marked live, R1's real `URLSessionTransport` against a loopback socket, with an injected clock. `MANIFEST.tsv` (SHA-256 `8e1b03e17095bf97f8c0a32e9174ad3aea399a5d0034f3984fbb71dc20829bdb`) lists each file's statuses, attempts, request identity, uncertainty, last error and SHA-256; `SHA256SUMS` (`e1f2c2e62f5711cad57c05d4568f01d264448b71a64ab547eb39983483eb1d56`) covers the 273 files outside `.build`. Every entry was checked field by field.
- **Coverage (plan §8.14.3 histories):** `unsent` (all nine mutation kinds, captures with and without titles, an idea with a title); `single` done (201), conflict (R1's 409s: "the task changed since it was read", "the task cannot move from …", "the item changed since it was read; reload it and try again"), failed (400 "send between 1 and 50 changes", 400 "unknown action" as a scripted answer, 404, 422 request ID reused, 500), and pending after 401, 429, 502, 503 (two messages), 504, connection refused and host unreachable; `unresolved`: timeout, cancellation and interruption after delivery (R1's only uncertain cases), a 504 then a 401, requeued after a conflict and after a failure, expiry after 30 days.
- **Not produced yet:** a raw `sending` file left by a killed process, with R1's recovery of it in a separate copy, and the before/after pair of completed-entry pruning. Both are due before S-01 (M3) and S-02 (M9) need them.
- **R1 behavior recorded for M9 (S-02):** R1 marks only a timeout, a reset after delivery and a cancellation as uncertain (`LisaClient/QueueSendOutcome.swift:38-58`), never a 504 or a "still being processed" 503; after a 504 then a 401 the 504's `nextAttemptAt` remains (`OfflineQueue+Flush.swift:124-128`); on Linux a refused connection and an unreachable host map to the same text; "unknown action" cannot occur between an R1 client and an R1 host.
- **Outside the run directory:** swift-corelibs-foundation created `~/.cache/org.swift.foundation.URLCache/frozen-client-harness/` when R1's transport first ran, as R1's own suite does for its runner; left in place.

### M0-6 Frozen R1 datasets (§8.18 step 3)

- **Commands:** the frozen release `lisa` (`34ef4335…9bff`) and its CLI only, with synthetic configs; live delivery only to responders on 127.0.0.1, ports 47100–47199, with synthetic recipients. Every step's command, UTC time and exit code is in each dataset's `logs/`; `COMMANDS.md` regenerates them. Inspection used copies opened read-only.
- **Datasets** in `m0/frozen-datasets/`: `ds-demo` and `ds-demo-debug` (`lisa demo`, release and debug, identical record counts) and `ds-deliveries`. `SHA256SUMS` (`ebfb139881c8cf643c17f752f32bcbe9d7a16491e33df34f13a1d051b9b7b641`) covers 206 files.
- **Delivery states produced by R1's own code:** `capturedDryRun` (8 push, 3 email), `pending` (3: quiet hours, a call escalation inside its grace, a live email retrying after a 421 greeting), `suppressed` (4), `cancelled` (9), `failed` (3: a 554 greeting, an untrusted certificate, a 421 whose retry fell after expiry), and `outcomeUnknown` (1: `lisa` killed while submitting a live email to a responder that never answered; after the 30-second lease R1's recovery recorded "the host stopped while the request was being submitted").
- **Also present:** one-off and daily repeating reminders, missed reminders suppressed by recovery, briefs, plans with proposed and locked blocks, schedule preferences, 11 tasks, an idea capture, 11 feed items, two paired devices and a revoked iPad.
- **Not produced yet:** `acceptedByProvider` (R1 verifies SMTP certificates against the system trust store only, so a controlled TLS server can't be trusted through configuration), `confirmedDelivered` (needs a device receipt through `lisa serve`), `inProgress`, model-budget consumption, the capture-title and shared-URL cases of §8.14.3, richer task revision histories and plan-block actions. They are due before S-02 and S-13 (M9) need them.
- **Clock:** except `lisa demo`, the commands used the real clock (2026-11-24, about 08:30–08:45 UTC), so a regeneration gets new identifiers and times.

### M0-7 Dependency change: swift-crypto 5.1.2 (`docs/DECISIONS.md` D-53)

- **Change:** `9e35866` (`Package.swift`, exact 5.1.2) and `fd94a78` (`Package.resolved`: revision `3280a5f72874d2f73bf25551bbb64f524c76d834`; lockfile `f8463195…c91e776`). SwiftPM's workspace state shows 5.1.2 checked out for both toolchains, with swift-asn1 1.7.4.
- **Regression:** the M0-1 procedure in fresh scratch paths (`.build/r2-dep-20261124-r2-5462/swift-crypto-5.1.2/swift-<version>`), script `.tmp/r2/20261124-r2-5462/deps/run-regression.sh`. **PASS** for 6.4.2 and 6.4.3, debug and release: exit 0, 0 warnings, 376 tests in 66 suites, the demo 30 of 30 each; runner SHA-256 6.4.2 debug `30c9ecd2611d6062…`, release `6b950c33bb59117c…`, 6.4.3 debug `f9a0f554bae07cba…`, release `feece55d21f7ae31…`. Evidence: `.tmp/r2/20261124-r2-5462/deps/regression-swift-crypto-5.1.2/`.

## 2a. M1 (run `20261124-r2-5462`)

### M1-1 Canonical JSON, base64url and transfer budgets (R2-L32; S-16 M1 part)

- **Code:** `LisaSyncProtocol` (`8244d48` … `4a8826b`).
- **Harness:** `.tmp/r2/20261124-r2-5462/m1/harness/`, a temporary package depending on the root package by path, swift-testing, public API only; built with `--force-resolved-versions` against a copy of the project lockfile, which SwiftPM left unchanged.
- **Vectors:** a representative value with every escape class, non-ASCII and astral text and the Int64 extremes, encoded byte for byte and decoded back; key order by Unicode scalar value (U+E000 before U+1F600, unlike UTF-16 order); canonically equivalent keys refused as duplicates and strings compared byte-exactly; nesting 16 accepted and 17 refused; size derivation with three-byte characters and escapes; refusal of whitespace, a BOM, empty input, trailing bytes, unsorted and duplicate keys, fractions, exponents, leading zeros, negative zero, Int64 overflow, seven invalid UTF-8 forms, lone surrogates, every non-minimal escape and raw control characters; an operation body of exactly 64 KiB accepted and one byte more refused; RFC 4648 base64url vectors and the plan's enrollment-token text `AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8`, with padding, foreign characters, impossible lengths and non-zero trailing bits refused; unknown, missing and mistyped fields refused; each transfer budget at its limit and one over.
- **Result: PASS**, 16 tests in 5 suites (Swift 6.4.2, debug). With the target added, a full debug build has 0 warnings and the unmodified R1 suite passes 376 tests in 66 suites. `swift format lint` reports no finding in `Sources/LisaSyncProtocol`.

## 3. Scenario index (plan §10.2)

Not run unless a row says otherwise. Each scenario's full content is in plan §10.2; its records join this file when its milestone runs it.

| ID | Subject | Milestones and sessions | Status |
|---|---|---|---|
| S-01 | v1 translation with the frozen R1 client, queue and CLI | M3 | Not run |
| S-02 | R1 queue classification and post-downgrade reconciliation | M9 | Not run |
| S-03 | The one legacy converter | M3, M9, X7 | Not run |
| S-04 | First-contact owner-text key in both TLS modes | M3, X2 | Not run |
| S-05 | Bounded device-only retry and the test-only enrollment-result fault | M3, X2 | Not run |
| S-06 | Snapshot installation under writes | M2 | M2 parts run (M2-11): installation under writes with searches, the backlog cases and boundary, a newer page and an older cut, restarts between steps, tampered and incomplete snapshots; kills inside the staging and swap transactions (M2-12); still to come: the windowed buckets' deferred pages and absence after the swap (with S-08) |
| S-07 | Pieces, value limits, reviewed-set artifacts | M2, M3, M5 | Not run |
| S-08 | Interval coverage and the planning-zone change | M2, M3, M6 | M2 parts run (M2-10, M2-13, M2-14): the cursor cases, deferral, the absence rule in both orders, non-nesting windows, rolling windows and moves, stale relayed pages, repairs by generation with the overlay watermark and constant-size publication; still to come: the zone-unverified floating rows and all-day rows read in the planning zone, searches around a repair, Core (M3) and the simulated link (M6) |
| S-09 | Backup lineage, anchors and discovery | M3 | Not run |
| S-10 | Re-anchoring, restore, fences and admission | M3 | Not run |
| S-11 | Delivery holds after a restore; (l) recorded against KF-1 | M3, M4, M8 | Not run |
| S-12 | Reminder firings and OS ownership; (m) recorded against KF-2 | M8, X6 | Not run |
| S-13 | Export, rollback and installation of either v4 database | M5, M9, X3, X7 | Not run |
| S-14 | The destination policy at every redirect | M7, X1, X5 | Not run |
| S-15 | VPN publishing | M4, target host | Not run |
| S-16 | Size boundaries and bounded dependency release | M1, M3, M6 | M1 part PASS (M1-1, M1-7: budgets, frame header); M3 and M6 parts not run |
| S-17 | SQLite readers, exhaustion and bursts | M2, M3 | M2 parts run: the single-writer guard (M2-0), `SQLITE_FULL` in a save (M2-3), the reader monitor, the pinned reader and the burst on a container tmpfs (M2-4), storage filling during a staged installation on the tmpfs and the peak sizes (M2-12); `max_page_count` on the Fedora host `NOT_RUN_ENVIRONMENT`; Core's part at M3 |
| S-18 | Model accounting | M7 | Not run |
| S-19 | Deletion and expiry propagation | M5, M8 | Not run |
| S-20 | Health, CLI modes and the deployment wrappers | M3, M4 | Not run |
| S-21 | Mail and calendar connectors against controlled servers | M7 | Not run |
| S-22 | Model adapters and the controlled local Ollama server | M7 | Not run |
| S-23 | Outbound email and calls against controlled servers | M8 | Not run |
| S-24 | The owner-verification harness itself | M1, then every milestone | M1 part PASS (M1-9: fixture mode, the ledger's four interruption variants, resume and retry, observations and paired joins, the redacted export, signed entitlements, cleanup); host steps (M3), provider grant isolation (M7) and the owners' signed builds not run |
| N-A | Narrative §19.1 | M3, M4, M8 | Not run |
| N-B | Narrative §19.2 | M9, X7 | Not run |

## 4. Collecting evidence outside the VM

Run directories exist only in this sandbox. Tracked records like this file reach the host when the owner fetches the branch's commits. For the raw evidence, Claude builds a redacted bundle on request (or at each milestone): a `.tar.gz` with a SHA-256 manifest, after a scan that masks tokens, account identifiers and e-mail addresses. The owner copies it out through a port the owner publishes; the exact command is in `R2-CHECKPOINT.md`.

### M1-2 LisaCrypto R2 primitives (plan §7.2.2; R2-L16 signature part)

- **Code:** `ec3784d` … `2abce7e` (`LisaCrypto`: canonical-DER P-256 keys, raw signatures, agreement with HKDF, HKDF and HMAC, HPKE).
- **Harness:** `.tmp/r2/20261124-r2-5462/m1/harness/` (target `CryptoTests`), copied unchanged into `m1/harness-v2/`.
- **Vectors:** HKDF-SHA256 RFC 5869 test case 1 and HMAC-SHA256 RFC 4231 test case 1 reproduced; truncated HMAC codes verified and refused when altered or shorter than 16 bytes; raw signatures of 64 bytes that verify, and refusal of a tampered message, a 63-byte signature and another key; canonical 91-byte SPKI only, with an extra byte, a truncated key, a changed curve byte, a point off the curve and the compressed-point form of the same key refused; both sides of a key agreement deriving the same HKDF key; HPKE P256_SHA256_AES_GCM_256 round trip with a 65-byte encapsulated key, and refusal of a wrong key, wrong info, wrong authenticated data and an altered ciphertext.
- **Result: PASS**, 6 tests.

### M1-3 LisaTrust: token, owner texts, signatures, nearby session layer (plan §8.1.2 M1 acceptance, §8.7)

- **Code:** `822ffe5` span (`LisaSyncProtocol` identifiers; `LisaTrust`).
- **Harness:** `.tmp/r2/20261124-r2-5462/m1/harness-v2/` (target `TrustTests`; run with `swift test --force-resolved-versions --manifest-cache none`).
- **Vectors:** the enrollment-token vector (`e74f49bf…13db`, `AAECAw…Hh8`) and refusal of other lengths and spellings; `lisa-pair:4:` round trips in `pin` and `ca` modes with the shared fixture of `docs/SYNC-PROTOCOL.md` §6, its SPKI parsed by OpenSSL as P-256 and its fingerprint, canonical payload and checksum reproduced in Python; every refusal vector listed there; `lisa-reanchor:2:` round trip, `lisa-reanchor:1:` refused as outdated and a pairing text refused as unknown; domain signatures that fail under another domain or with one byte added; Design A pair keys agreeing in both directions and the discovery-tag and rejoin vectors reproduced with Python's `hmac`; exporter-bound nearby authentication verifying for the genuine transcript and failing for another key, another exporter value (the relay case) and the other role, with identical devices, a short exporter and a short nonce refused.
- **Result: PASS**, 11 tests in 3 suites.

### M1-4 Operation envelope, digests, signatures and identity (R2-L05 codec part, R2-L16 signature and dataset part, R2-L32)

- **Code:** `e7e5085` span (`LisaSyncProtocol` envelope types; `LisaTrust` digest, signing, legacy child identity).
- **Harness:** `m1/harness-v2/`, targets `EnvelopeTests` and `EnvelopeTestsV2`.
- **Vectors and cases:** byte-exact round trip and SHA-256 digest of the exact body; each malformed rule (device operation with `legacyParent` or without `createdAt`, legacy origin without `legacyParent`, 33 dependencies, unsorted and self dependencies, 257 observed pieces, an incarnation link on sequence 2, an unknown field, protocol version 1, an unknown type, an uppercase identifier, a body over 64 KiB); verification refusing another dataset, a signature from another body, a forged signature, an unknown origin and a device-signed legacy child, and accepting a Core-signed one; the duplicate, identity-reuse (a legacy child with another digest included), sequence-reuse and new verdicts; the legacy child-ID and set-digest vectors; the value budget for four types filling exactly 65,536 bytes with worst-case escaping, one byte more refused.
- **Result: PASS** for every case of `EnvelopeTests` except its value-budget test, and **PASS** for `EnvelopeTestsV2`. The failing v1 test is a harness error, kept unchanged and recorded in `m1/harness-v2/NOTES.md`: it rebuilt only the device envelope, while the derivation takes the larger legacy envelope. `EnvelopeTestsV2` checks both variants.

### M1-5 Merkle paging (M1 "Merkle paging vectors"; R2-L16 part)

- **Code:** `bfe0efd` … `13ce72c` (`PagedArtifact`, `MerkleTree`, `PagedArtifactVerification`, the header signing domain).
- **Harness:** `m1/harness-v2/`, targets `MerkleTests` and `MerkleTestsV2`.
- **Vectors and cases:** roots for 1, 2, 3, 5, 7 and 8 pages and two inclusion proofs from an independent Python RFC 6962 implementation; for every tree of 1 to 33 pages, each page verifying at its own index under the signed size and at no other index, with an altered page, an out-of-range index and a shortened proof refused; a whole artifact accepted in any arrival order and refused for a dropped, repeated, swapped or altered page, a forged header and another dataset; a header inflated by one page refused without a new Core signature.
- **Result: PASS** for the roots, the artifact cases and `MerkleTestsV2`. `MerkleTests`' proof test fails with exactly 448 issues, a harness error recorded in `m1/harness-v2/NOTES-2.md`: it expected verification to refuse a proof under a tree size one larger, which RFC 9162's algorithm does not authenticate. The Python implementation accepts the same 448 cases, so the Swift verifier matches it exactly, and the product takes the size only from Core's signed header.

### M1-6 Protected archive codec (the codec part of S-13; its full cases are M5)

- **Code:** `AESGCM256` and the archive domain, then `LisaArchive` through `505ee96`.
- **Harness:** `m1/harness-v2/`, target `ArchiveTests`.
- **Cases:** sealed to a Core roster key and this installation's key and signed: the file parses back identically, both keys open it to the exact entries, the device's signature verifies and another key's does not; an installation-only archive refused to another installation's key; another dataset refused; one ciphertext byte altered fails decryption and authenticity; a header changed and re-encoded canonically fails decryption (the header digest is the authenticated data) and authenticity; an unsigned archive opens but is never authentic; an archive sealed to a key later retired opens with that key; a bad magic, a truncated file, trailing bytes, a signature flag of 2, a signature with no named signer and a cut header refused.
- **Result: PASS**, 4 tests.

**After each span:** a full debug build has 0 warnings, `swift format lint` reports no finding in the changed modules, and the unmodified R1 suite passes 376 tests in 66 suites (Swift 6.4.2).

### M1-7 Nearby wire contracts: frame header and hello form (R2-L32; S-16 M1 part; plan §8.7, §8.16.2)

- **Code:** `NearbyFrameError` and `NearbyFrameHeader` (`LisaSyncProtocol`), `NearbyHello+CanonicalBody` (`LisaTrust`): `c096983`–`c69586c`.
- **Harness:** `m1/harness-v3/` (v2's current targets linked, plus `NearbyWireTests`; the superseded v1 tests and the type-check directories left out).
- **Cases:**
  - the documented header layout, with exact bytes for a 5-byte payload, an empty frame and the 1 MiB frame;
  - a round trip over every boundary length and several kinds;
  - refusal of 1 MiB + 1, `Int.max` (no overflow trap), negative and `Int.min` payloads;
  - headers of 7, 9 and 0 bytes, totals 0–7 and above the budget, version 0 or 2, and non-zero reserved bytes, each refused before any payload;
  - the hello against a vector computed independently with Python;
  - another protocol version, an unknown or missing member, a short nonce, uppercase hex, whitespace, wrong key order, a trailing byte and a body over 4 KiB, each refused.
- **Result: PASS**, 6 tests in 2 suites, with all 46 tests of v3's other targets.

### M1-8 The X1 proof app `Apps/Proof` (plan §8.7, §8.9.3, §10.5 N-1 and E-1, §10.6 X1; `docs/DECISIONS.md` D-54)

- **Code:** 69 Swift files, 4 configuration files and the `LisaProof` target: `bc11c09`–`559f4bb`. The draft was reviewed against HEAD and the plan before integration.
- **Linux checks** (no Apple build or run is claimed; that is X1's):
  - `swiftc -parse`: 69 of 69 files (`m1/proof-parse-repo-*.log`).
  - The 38 files without an Apple-only import type-checked against HEAD's `LisaCrypto`, `LisaSyncProtocol`, `LisaTrust` and `LisaHTTP`, with Linux stand-ins only for Apple-only types (`m1/proof-typecheck-repo-*`): exit 0, no warning.
  - The certificate encoder's DER verified with OpenSSL 3.5.9 (`m1/proof-proposal/cert-check/`).
- **First failures and fixes, found by the review and the type-check:**
  - `Result<…, String>` doesn't compile, since `String` isn't an `Error`; it now returns a refusal type.
  - A missing `import Security`.
  - Design B's unenrolled-identity fault presented the enrolled certificate, so roster pinning was never exercised. It now presents a throwaway Secure Enclave identity that no roster lists.
  - References to temporary notes were replaced by D-54.
  - The frame header and hello now come from the portable modules.
- **Result:** ready for X1 (owner-run). N-1, E-1 and E-2 stay open until the owner's results.

### M1-9 The owner-verification harness core and S-24 at M1 (plan §10.8; R2-DEV-02)

- **Code** (`Harness/`, linked by no product, `Package.resolved` unchanged):
  - `LisaVerifyKit`: IDs, statuses, case model, result schema, run store, action ledger, pair sessions, observations, imports, report, redaction and export, Apple preflight, cleanup.
  - `LisaVerifyCases`: the X1 and harness catalogues, the fixture action executor and crash points.
  - `LisaVerifyServers`: the counting and classifying controlled servers, SMTP and HTTP in the APNs, OpenAI, Anthropic, Ollama and Twilio shapes, on SwiftNIO.
  - `lisa-verify`: quickstart, preflight, cases, guide, run, pair-session, observe, import-diagnostics, report, export, resume, retry, actions, authorize-retry, cleanup.
  - Documents: `Harness/README.md`, `Harness/docs/` (`SETUP-APPLE.md`, `PAIRED-SESSIONS.md`, `RESULTS.md`, `CASES.md`, `CLEANUP.md`), `Harness/config/owner-verify.example.json5`.
  - `Apps/OwnerVerification`: the UI smoke test, test plan X1, the `LisaProof` scheme.
  - Commits `8e58552`–`d0a9e53`.
- **Temporary checks:**
  - `m1/harness-v4/`: 13 tests (IDs, run store, proof-shaped lines, ledger rules, imports, report, observation, canary export).
  - `m1/harness-v5/`: 3 tests (the servers over real loopback connections).
  - An end-to-end CLI run (`m1/cli-e2e-*`).
- **S-24 fixture run** (`lisa-verify run --mode fixture`, `m1/s24-20261124T133622Z/`, run `run-20261124T133622Z-kldvy6`): **9 of 9 PASS**, 25 logical actions.
  - (i) Killed by SIGKILL after the intent: resumed in a new process with one accepted submission, for each of email, push, model request and call.
  - (ii) Killed after the server accepted: found by the server's lookup and recorded "accepted (observed)", never resent.
  - (iii) Accepted and dropped with the lookup disabled: ambiguous. Resume sent nothing, `authorize-retry` without the typed phrase sent nothing, and with it exactly one more was accepted, reported as a possible duplicate.
  - (iv) A new action refused under the old confirmation, then accepted under a new one.
  - An interrupted case resumed, and one failed case reran alone.
  - A manual observation, and paired results joined only under one nonce.
  - No planted canary in the export.
  - Signed entitlements decided for both platform keys, a missing key, mismatched environment and topic, an unlisted device and an expired profile.
  - Cleanup of the run's own data only.
- **Not covered at M1:** host steps and the verification Core (M3), provider grant isolation (M7), and validation of the owner's actual signed builds (X1 onward). `preflight apple` reports `NOT_RUN_ENVIRONMENT` on this Linux host.

### M1 boundary: a clean checkout (plan §9: builds, lint, harness from a clean checkout in fixture mode)

- **Method:** `d0a9e53` reconstructed with `git show` into `m1/clean-20261124T134046Z/tree/`: 1,084 files, each byte-exact against `git rev-parse`; manifest SHA-256 `4febba75…713236`.
- **Results** (Swift 6.4.2, fresh scratch paths; the commits after `d0a9e53` change documents only):
  - Debug build with tests: exit 0, 0 warnings.
  - The unmodified R1 suite: **376 tests in 66 suites passed**.
  - `swift run lisa-verify run --mode fixture` (run `run-20261124T134144Z-4x753a`): **9 of 9 PASS**.
  - Release build: exit 0, 0 warnings.
  - `swift format lint` of `Sources`, `Tests`, `Harness`, `Apps` and `Package.swift`: only R1's own `Package.swift` line (R1 line 148), unchanged since `491c90a`.
- **Evidence:** `m1/clean-20261124T134046Z/` (`*.log`, `*.exit`, `runner.sha256`, `matrix.sh`).

## 2b. M2 (run `20261124-r2-5462`)

### M2-0 SQLite's WAL-reset bug: the loaded library and the single-writer guard (S-17 part; `docs/DECISIONS.md` D-55)

- **The library:** `libsqlite3-0` 3.46.1-7+deb13u2+dhi4.
  - Debian's packaging for 3.46.1-7+deb13u2 was fetched from deb.debian.org; its SHA-256 matches the `.dsc`.
  - Its changelog and 15 patches have no WAL fix. The DHI rebuild's changes aren't published.
  - The library is therefore treated as unfixed (`m2/sqlite-src-20261124T134427Z/`).
- **Code:** `SQLiteWriterLock`, `SQLiteCheckpointMode`, `SQLiteCheckpointResult` and `SQLiteWALDatabase` (`LisaSQLite`), `c9fed41`.
- **Harness:** `m2/harness-v6/`, 4 tests.
  - A second writer is refused in this process and from another process.
  - Read-only connections can neither write nor checkpoint.
  - A read-only connection closing last leaves the WAL and the database file byte-identical.
  - The writer's TRUNCATE checkpoint empties the WAL.
- **Result: PASS.** After the span, a full debug build with tests has 0 warnings and the unmodified R1 suite passes 376 tests in 66 suites (`m2/suite-after-walguard-rerun-*`).
- **Environment event:** the first suite run after the span failed to link: the project volume was full (49 GB, 5.6 MB free). The SwiftPM scratch outputs of superseded builds under `.build/` were removed (24 GB). They are ordinary build output, not temporary files (`CONSTRICTION.md`); their logs and runner hashes are kept in `.tmp/`, which wasn't touched. The rerun passed as above, and routine builds now reuse `.build/r2-run`.

### M2-1 LisaMerge: the merge rules' state (R2-L11 part; plan §8.3.1, §8.3.2)

- **Code:** `MergeAuthority`, `CommitPosition`, `ObservedCoverage`, `MultiValueRegister`, `ObservedRemoveSet`, `TerminalActions`, `FiringResponses`, `ItemTombstone`, and the `LisaMerge` target: `72797e1` and the commits before it.
- **Harness:** `m2/harness-v9/`, 7 tests.
  - v7's test file didn't compile under Swift 6's concurrency checking, and v8's had a mutating call inside `#expect`. Each was superseded by a new harness copy; neither was edited.
- **Cases:**
  - Every permutation of a representative operation set converges. For the register, all 120 orders give the owner conflict B/C, with model and source suggestions M/S.
  - An owner write replaces what it observed, whatever its authority; a model or source write never replaces an owner or ambiguous value.
  - A piece committed later is judged by the stored horizon. A piece committed after the horizon, or in another epoch, stays.
  - The observed-remove set keeps a concurrent addition.
  - A reopen leaves an unseen cancellation in effect, and completion with cancellation shows as "completed and cancelled".
  - The latest snooze is capped at the maximum, and a settlement suppresses the firing while keeping the snoozes in history.
  - The tombstone dominates in either order.
- **Result: PASS.**

### M2-2 Causal readiness and bounded release (S-16 part; plan §8.2.2)

- **Code:** `CausalRelease` (`LisaMerge`), `386a738`: the reference algorithm the replica store and Core's ledger persist.
- **Harness:** `m2/harness-v10/`, 4 tests, 9.3 s in debug.
- **Cases:**
  - The plan's nested fan-out: one decision releases 5,000 dependents, each with 20 dependents (105,001 operations). All are applied in causal order, and no expansion or release step exceeds 256 edges, enqueues or releases.
  - 33 dependencies are refused as malformed.
  - A forged two-operation cycle rejects both members, and their dependents are released.
  - Release is round-robin across origins: 128 + 128 in the first step.
  - A copy taken mid-drain reaches the same decisions.
- **Result: PASS.** The durable markers, cursors and queue, and the kill at each step, are tested with the stores (M2 replica, M3 Core).


### M2-3 LisaReplicaStore, first span (R2-DATA-01, -02, R2-SYNC-02, -04 parts; plan §8.1.1, §8.2.1, §8.6.1–§8.6.4; S-17 in-database part)

- **Code:** `LisaReplicaStore`, `ef9f546` → `818fe3c`. It starts with the observed set's canonical form in LisaSyncProtocol and ends with `Package.swift`; D-56 is `528f236`.
- **Harness:** `m2/harness-v12/`, 9 tests through the public API on real files under `m2/harness-v12-work-*`.
  - v11 didn't compile: a `Digest256` built inside a `do` block widened its error type. It is superseded and kept unchanged.
  - v12 was rerun after formatting: 9/9 again.
- **Cases:**
  - **Directory and schema:**
    - The replica directory and its folders are 0700; the database, its WAL and the ballast (written zeros) are 0600.
    - Schema v1 has 18 tables.
    - A second writer is refused while the first is open.
  - **Before enrollment:** a save is a draft ("not enrolled") with its follow-up. After enrollment the draft is signed under its own operation ID and original time, at sequence 1, and verifies with the device key.
  - **Key unavailable:** a save is a draft ("key unavailable") and consumes no sequence. A later launch signs it, and its link skips the empty incarnation: (I1, 1).
  - **The restored copy (§8.6.4, M2 replica side):**
    - A copy of the closed replica, taken with its key and restored after the device continued (I2, two more operations), starts I3, linked to (I1, 3) as I2 is.
    - Across both copies, no origin triple names two operations.
    - Exchanging the journals stores the new entries and returns `duplicate` for the three shared ones, with no security event.
  - **The duplicate rules on a replica:**
    - The same ID and digest is `duplicate`.
    - The same ID with another digest is `identity_reuse`.
    - Another ID with the same triple is `sequence_reuse`.
    - Each refusal records a security event with both digests.
    - Another dataset, a forged signature and an unknown device are refused before the rules apply.
    - The replica's own operation relayed back is a duplicate.
  - **The atomic local change rolls back:**
    - An index failure rolls everything back: journal, generation, sequence, follow-ups and the index's own rows.
    - So does `SQLITE_FULL`, forced with `max_page_count` inside the transaction and reported as "storage full".
    - An earlier save stays intact, and the next save takes sequence 2.
  - **The overlay stays until the canonical change installs (§8.6.4):**
    - It stays through provisional and final receipts, and leaves when the row containing it installs.
    - A repeated receipt, and a changed final decision, change nothing. A receipt for another digest is refused.
    - An older row version is ignored, and a newer tombstone installs.
    - A rejection leaves the view at once and stays in the journal.
    - The local change journal records exactly these changes, in order.
  - **Invalid commands:** an unknown operation or entity type, 33 dependencies, and a body over 64 KiB are refused before anything is written.
  - **Local changes:** they are read in order after any generation, and sequences are consecutive within an incarnation.
- **Full build and R1 suite after the span:** `m2/suite-after-replica-span1-20261124T205211Z/`. The debug build with tests has 0 warnings, and 376 tests in 66 suites passed. The runner is unchanged (`8816964d…`) because R1's tests link no R2 module.
- **Result: PASS.**
- **Still to come in M2:**
  - the effective view through LisaMerge, and CausalRelease persisted;
  - pages, cursors, memberships and deferred pages;
  - staged installation (S-06);
  - the reader monitor and the container exhaustion runs (S-17);
  - kills at each step on real files.

### M2-4 The reader monitor and the capture path, with the first container use (S-17 M2 parts; plan §8.15.2, §9 M2, O-10)

- **Code:**
  - `LisaSQLite`, `5d9a9c6` → `58aea5f`: interrupt, the interrupt and full error classes, free space, reader purposes and releases, and `SQLiteReaderMonitor`.
  - `LisaReplicaStore`, `94cf891` → `0aac9d1`: the ballast on the capture path, and long reads under the monitor.
- **Host harness:** `m2/harness-v13/`, run with `LISA_HARNESS_WORK` under the run directory.
  - **First run** (`harness-v13-test-20261124T210301Z.log`): 2 of the 3 host tests passed. `theSamplerReleasesOnItsOwnAndNeverKeepsTheReplicaOpen` failed: the released reader's error arrived before the monitor had recorded the release and run its checkpoint. An immediate retry could therefore have pinned the WAL again before it was truncated.
  - **Fix, in the product:** a released reader now returns only after the checkpoint (bounded at 5 s). The harness is unchanged.
  - **Since then:** 5/5 (3 host tests and 2 container-only tests skipped on the host), and again after formatting.
  - **Cases:**
    - A reader pinned during 300 captures: the WAL grew from 144 KB to 12 MB. The reader was released at its budget (300 ms for the test), the truncating checkpoint wasn't blocked, the WAL ended at 0 bytes, and all 300 captures were present.
    - Free space below the reserve released both readers within their 60 s budgets.
    - A sampling thread at 100 ms released a reader on its own within 3 s. The released store didn't keep the replica open: the next launch opened it as the second incarnation.
- **The first container use, labeled:**
  - **Engine:** the rootful Docker daemon inside `lisa.lab`, authorized by the owner. This is not rootless; G2 still needs rootless evidence.
  - **Platform:** Engine 29.10.0 (API 1.57), context `default`, the DHI Debian 13 VM, kernel 7.0.14, x86_64, cgroup v2 (cgroupfs), seccomp builtin.
  - **Image:** `swift:6.4.2-trixie` pulled by its O-3 digest `sha256:9733821cc4c736ac43a2b400b2bd08aa54fc7d98c9f58270a7392d7623430097` (amd64 manifest `8287f5cc…69d90`). It ships Swift 6.4.2 and `libsqlite3-0` 3.46.1-7+deb13u2.
  - **Test binary:** the v13 runner, built on this host, ran on the image's own Swift runtime (`LD_LIBRARY_PATH=/usr/lib/swift/linux`). Runner `1864bdb8…`, test library `fd7595d8…`.
  - **Containers:** each test ran alone in a new container with no network, the repository mounted read-only, and the replica directory on `--tmpfs /tmpfs-work:size=48m`.
  - **Evidence:** script `m2/container-20261124T2100Z/run-s17-v1.sh`; runs `run-20261124T210449Z` and `run-20261124T210552Z`, with the same binaries and outcomes.
- **Container cases:**
  - **A burst that fills the tmpfs between samples:**
    - Five captures were saved first. Then another writer filled the tmpfs to 0 bytes free (45 MB), and kept refilling it after every capture.
    - The first capture after that was saved through the ballast, and "Storage is almost full" held. The next 39 were all reported "Not saved".
    - With space back, the replica opened with exactly the 6 captures reported saved. `integrity_check` was ok, and the ballast was restored.
  - **A pinned reader (a 2 s search budget) during continuous captures:** 882 and 827 captures, WAL peaks of 41.9 MB and 39.2 MB. The reader was released at the space threshold after 0.25 s, the first sample, before its budget. The truncating checkpoint completed, leaving 0 WAL frames.
- **Observation, not a failure of these checks:** at 0 bytes free the replica couldn't be reopened ("storage full"). Opening records a new incarnation, and WAL mode needs room for its `-wal` and `-shm` files.
  - Every save stayed intact, and the replica opened as soon as space returned.
  - The app's launch path (M5) reports "Storage is full" without the replica, and retries the open when space returns.
  - Whether the ballast may also be released to open the replica is a question for the owner (`R2-CHECKPOINT.md` §5).
- **Full build and R1 suite:** `m2/suite-after-storage-span-20261124T210553Z/` — debug build with tests, 0 warnings; 376 tests in 66 suites passed.
- **Result: PASS** for these S-17 parts.
- **S-17 at M2 still owes:**
  - storage filling during a staged installation (with S-06);
  - `max_page_count` on the in-database path of staging (the save path is M2-3);
  - the peak staging, index and WAL sizes during an installation.

### M2-5 The task family's payload schemas and one task merged (R2-L11 part, S-07 M2 replica part; plan §8.2.3, §8.3.1–§8.3.3)

- **Code:**
  - LisaSyncProtocol `57c50b0` → `75326ea`: the deadline, task fields and values, the creation, and `ItemOperationPayload`.
  - LisaMerge `f093e69` → `8e0e73b`: `NotePieces`, `TaskView`, `TaskMergeState`.
  - The replica store's payload checks, on saves and on arrivals: `4e0c1e3`.
  - Documented in `docs/SYNC-PROTOCOL.md` "Item payloads" (`43b5369`) and `docs/CONFLICTS.md` (`fae2ba7`).
- **Harnesses (first outcomes kept):**
  - **v14:** never built. Read before its first build, its test file had the same mixed-error `do` block as v11.
  - **v15:** v14 corrected, 7/7 on its first run.
  - **v12, rerun after the schemas:** 7 of 9 failed. Their fixtures send `task.create` with only a title, which the store now refuses as an invalid command. That is the intended behavior; v12 is kept as recorded.
  - **v16:** v12's tests with schema payloads, plus an arriving-payload test. 9 of 10 passed. The new test expected the decoder to name `confirmation` as the missing field; it names the first missing field in field order, `priority`. Because of that, the test never reached its "nothing stored" check.
  - **v17:** v16 corrected, 10/10.
  - **v13:** 5/5 again.
- **Cases:**
  - **Payloads:** canonical forms round-trip for every type (the vectors in `docs/SYNC-PROTOCOL.md`). Each of these is refused:
    - an empty or 201-character title (200 is accepted);
    - a missing or unknown field;
    - an unknown priority, an estimate of 0, an unknown field name, or a value of the wrong type;
    - 2026-02-29 (2028-02-29 is accepted);
    - a zone containing other characters;
    - an empty or unsorted reopen list;
    - an unknown tag change, or a 65-character tag;
    - fields on `task.complete`;
    - an empty note.
  - **The note budget (S-07, M2 replica part):**
    - The largest note, 53,983 encoded bytes built from `\u0001` escapes, is saved; its operation body is 54,422 bytes.
    - One byte more is refused as `invalidCommand(encoding(tooLarge(53984, 53983)))` before the operation is built.
    - A `task.complete` naming an idea is refused.
  - **An arriving `task.create` with only a title:** refused as `unverified(malformed(missing priority))`, with nothing stored and the generation unchanged.
  - **Convergence (R2-L11 part):** every permutation gives one state and one view.
    - **Concurrent title edits, a priority edit, two notes and a replacement that saw one of them** (5,040 orders): a title conflict between the two edits; priority high; the unseen note kept beside the replacement. Re-applying operations changes nothing.
    - **Tags and status** (5,040 orders): a removal of "health" that also observed the "errands" addition leaves "errands". Concurrent completion and cancellation, with a reopen naming only the completion, end cancelled.
    - **A deletion with concurrent edits** (24 orders): deleted, with both edits recorded as superseded.
    - **Horizons through position 12** (40,320 orders):
      - A replacement removes the note committed at 11, but not the one at 13 or a pending one.
      - A tag removal removes "health" (committed at 12), but not "errands", committed at the same position.
      - Applying everything pending and learning the commits afterwards gives the same state.
- **Full build and R1 suite:** `m2/suite-after-payload-schemas-20261124T211753Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**
- **Still to come:**
  - the other types' payloads, the authority path's source and model values in these registers, and restores;
  - the replica's effective view through `TaskMergeState`;
  - S-07's paged resolution group with 1,000 candidates.

### M2-6 The replica's effective view and its persisted causal release (S-16 replica part, R2-L11 part; plan §8.2.2, §8.6.1)

- **Code:** `83791b1` → `09cf01a`:
  - collection partitions;
  - LisaMerge joining the store;
  - draft items and the edge index in schema v1;
  - `CausalStep` and `CausalReleaseTables`;
  - the store's view and release.
- **The rules:**
  - A local operation enters the effective view at once.
  - A relayed one waits until every dependency is decided. Each step is its own transaction.
  - An expansion step reads at most 256 edges in all, across the oldest markers.
  - A release step applies at most 256 ready operations, oldest first and round-robin across origins.
  - A task's view merges its applied, unrejected entries, with their commit positions, and its held drafts through `TaskMergeState`.
- **Harness:** `m2/harness-v19/`, 4/4 on its first run.
  - **v18 was never run.** Its step counts assumed one marker per expansion step, which leaves one empty step for every released operation. The product was changed to read edges across markers within the same 256-edge bound before v18 was built.
  - Harnesses v13, v15 and v17 pass again.
- **Cases:**
  - **Local changes:**
    - A draft before enrollment is already in the view, and stays there once signed.
    - An edit that observed the creation replaces its title. When Core rejects the edit, the view returns to the creation's title.
    - An unknown task has no view.
  - **A relayed edit that arrives before its creation:**
    - It is stored but not in the view, and the task has no view.
    - Once the creation arrives, the steps are exactly: release the creation; expand (1 edge, 1 enqueued); release the edit; expand (0).
    - The view then shows the renamed title. The local change journal records the two releases in causal order.
  - **Fan-out (S-16 replica part):**
    - 700 note dependents of one relayed creation arrived first: 600 from one peer, 100 from another.
    - Releases came in sizes of 1, 256, 256 and 188, with no step over 256 edges, enqueues or releases.
    - The first full release held all 100 of the second peer's operations, round-robin.
    - The replica was closed after three steps and reopened, and the drain resumed from the tables: 10 steps in all.
    - 701 operations were released exactly once, and the view shows 700 notes.
  - **A forged two-operation cycle:** both members are rejected when the second arrives, nothing waits, one step clears their markers, and neither enters the view.
- **Full build and R1 suite:** `m2/suite-after-effective-view-20261124T212729Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**
- **Still to come:** process kills inside a step on real files (a step is one transaction, so SQLite's rollback is what they test), canonical rows from Core's pages in the view (M3 defines their pieces), and the other types' views.

### M2-7 LisaLocalSearch: the token index behind ReplicaIndexing (S-06 and S-08 search parts, in their M2 preliminaries; plan §8.6.1, §8.15.2)

- **Code:** `8b5cb7e` → `cd37d4f`. The postings table is in schema v1, and the store provides `searchableText`. `SearchTokenizer` and `LocalSearchIndex` follow, with D-57 and `Package.swift`.
- **The rules:**
  - An item's postings are replaced in the same transaction as its effective view.
  - Tokens are folded for case, diacritics and width.
  - A search finds the items holding every query token, on one snapshot, as a long reader under the reader monitor.
- **Harness:** `m2/harness-v20/`, 3/3 on its first run.
  - **v17, rerun after this span:** 1 of 10 failed. Its pinned table list predates `search_postings`; v17 is kept as recorded.
  - **v21:** the updated list, 10/10.
  - v13, v15 and v19 pass again.
- **Cases:**
  - **A local edit and its rejection:**
    - "Dentist appointment" is found by "dentist", whatever the case.
    - After the edit to "Orthodontist…", "dentist" finds nothing and "orthodontist" finds the task.
    - After Core rejects the edit, the reverse holds again.
  - **A note and a deletion:** a note "Bring the Zürich referral" is found by "zurich referral", but not by "zurich invoice". After deletion, nothing is found.
  - **A relayed rename waiting for its creation:** neither title is found while it waits. Once released, the new title is found and the old one isn't, and so after a restart.
  - **A seeded random sequence:** 300 steps over five tasks (creations, title edits observing the last, notes, rejections, deletions). After every step, each of 6 probe words found exactly the tasks whose view holds it, with 0 mismatches.
- **Full build and R1 suite:** `m2/suite-after-local-search-20261124T213244Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**
- **Still to come:**
  - the staged index and its swap (S-06);
  - the searches scoped to days (S-08);
  - a materialized effective view: today the view is folded on demand. The random sequence took 16 s, mostly that fold, and staged installation needs materialized view tables anyway.

### M2-8 Paged resolution groups and the advisory note limit (S-07 M2 replica part; plan §8.3.2, §8.3.3)

- **Code:** `9c88032` → `3fb9b7f`: the `conflict.resolve` payload, its merge, `aggregateLimit`, and in the store the value rules, group assembly and advisory limit. Documented in `docs/SYNC-PROTOCOL.md`.
- **Harnesses (first outcomes kept):**
  - **v22:** never built. Read first, one refusal expected the wrong field and it used a tuple key path.
  - **v23:** didn't compile: an unmarked throwing initializer, and two `do` blocks mixing error types.
  - **v24:** built its group pages 0-based, and the protocol's `ResolutionGroupPage` refused them: pages are numbered 1…count. The store's new code had made the same 0-based assumption about the last page, and it was fixed to 1-based before v25.
  - **v25:** 6/6.
  - v13, v15, v19, v20 and v21 pass again.
- **Cases:**
  - **A four-page group over 1,000 pending candidates:**
    - A task's title has 1,000 concurrent candidates. The owner's resolution becomes pages of 256, 256, 256 and 232 IDs, each depending on the previous.
    - After each of the first three pages the title is still a 1,000-way conflict. After the last page it is "Resolved" alone.
    - A later candidate that the owner never reviewed stays beside it as a new conflict.
  - **The same group relayed from a peer, with page 2 withheld:** page 1 is released, pages 3 and 4 wait, and the title stays unresolved. When page 2 arrives, all of them release and the title is resolved, with nothing left waiting.
  - **A group whose list digest doesn't match:** never applied.
  - **Refused, before anything is written:** a resolution without its value, a value on page 1 of 2, and a title value under `priority`.
  - **Two maximum-size notes (53,983 encoded bytes each) from two peers:** received in both arrival orders by two replicas, they give identical views with both notes whole.
  - **The advisory limit:** after 1,000 notes, this replica's next note is refused (`aggregateLimit("notes")`), while a peer's note is still merged, giving 1,001.
- **Full build and R1 suite:** `m2/suite-after-resolution-groups-20261124T214107Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**
- **What this leaves of S-07:** the replica part's three cases (the largest values, concurrent maximum-size edits and notes, the four-page group) now have M2 evidence in M2-5 and M2-8. Exports (M5) and Core (M3) remain.

### M2-9 LisaTime: the monotonic clock with boot time (plan §7.2.2, §7.2.3, §8.11.4)

- **Code:** `6279859` → `437ca91`: `MonotonicInstant`, the `MonotonicClock` port, `BootTimeClock` (CLOCK_BOOTTIME on Linux, CLOCK_MONOTONIC on Apple platforms) and `ManualMonotonicClock`.
- **Harness:** `m2/harness-v26/`.
  - **First run:** 2 of 3 passed. The arithmetic test found a real bug: a move by a duration too large for 64-bit nanoseconds was capped at about 292 years instead of saturating at the largest instant.
  - **Fix, in the product, before the commit:** moves now saturate on any overflow, never below boot and never past the largest instant.
  - **Since then:** 3/3, with the harness unchanged.
- **Cases:**
  - The boot clock never went back over 100,000 reads.
  - The boot clock read 4,685.2369 s, between two reads of `/proc/uptime` by another process (4,685.23 s both, at its 10 ms resolution). So it is the kernel's boot-time clock, shared across processes.
  - Instant arithmetic saturates at both ends.
  - The manual clock ignores a backward move.
- **Not run here:** a wall-clock step. Changing this host's clock needs root, and the boot clock doesn't read the wall clock.
- **Full build and R1 suite:** `m2/suite-after-monotonic-clock-20261124T214341Z/`: debug build 0 warnings, 376 tests in 66 suites passed. `LisaTime` is linked by R1, so this run exercised the change.
  - **Correction to commit `437ca91`'s message:** the build relinked the suite's test library `LisaTests.so` (`443303a7…`, `testlib.sha256`). The runner launcher was rewritten but is byte-identical (`8816964d…`), because the suite's code is in the library.
- **Result: PASS.** The clock's users (timeouts, backoff, freshness, `health.json`) adopt it at their milestones.

### M2-10 Signed change pages and partition cursors on the replica (S-08 replica part, unwindowed partitions; plan §8.4.2, §8.4.3)

- **Code:**
  - LisaSyncProtocol, `839e52e` → `62ce432`: the entry, the page, the signed page.
  - LisaTrust, `f0e04d8` → `6eeec5e`: the change-page domain and the verifier.
  - LisaReplicaStore, `2fa6981` → `8afac3b`: `canonical_operations`, the cursor types, `CanonicalTables`, and the store's page application, repairs and canonical fold.
  - Documented in `docs/SYNC-PROTOCOL.md` §8a.
- **Harnesses (first outcomes kept):**
  - **v27:** 5 of 6 passed. Its test roster left out the replica's own device key, so the replica's own committed operations in a page were refused as `originKeyMismatch`, which is correct.
  - **v28:** the same tests with the full roster, 6/6.
  - **v21:** its pinned table list predates `canonical_operations`. **v29** has the updated list, 10/10.
  - v13, v15, v19, v20 and v25 pass again.
- **Cases:**
  - **The four cursor cases on one partition:**
    - `(0,10]` with a creation at 3 and an edit at 7 → applied, cursor 10, the edited title shown.
    - `(2,8]` → ignored at 10.
    - `(8,15]` with entries at 9 and 12 → the one at 9 trimmed, the one at 12 applied, cursor 15.
    - `(20,25]` → a gap at 15.
    - `(15,20]` with no entries → proved unchanged, cursor 20.
  - **Pending local operations decided through a page:**
    - A pending note committed at 6 records its position, stops being an overlay, and is shown once.
    - A pending edit rejected at 8 leaves the view; the creation's title returns, and no follow-up is left.
  - **A repair:**
    - While repairing, a page `(10,20]` is deferred, and the cursor stays at 10.
    - Publishing at cut 12 applies the deferred page for that partition: cursor 20, the note shown.
  - **One page over two partitions:** `tasks` (cursor 10) is applied through 14. `ideas`, which has no cursor, is a gap, because the page doesn't start at 0.
  - **Refused, with nothing changed (no cursor, no view, generation 0):**
    - a page whose partition list was altered after signing: `unverifiedPage(invalidSignature)`;
    - a validly signed page carrying an operation by a device outside the roster: `unverified(originKeyMismatch)`.
  - **A relayed edit waiting for its creation:** it is released once the creation arrives as a canonical entry. After a restart, the view and cursor are the same, and the same page is ignored.
- **Full build and R1 suite:** `m2/suite-after-change-pages-20261124T215237Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**
- **Still to come for S-08's replica part:**
  - windowed calendar buckets, with membership ranges and the absence rule;
  - rolling windows;
  - the planning-zone cases;
  - the overlay watermark and constant-size publication;
  - repairs from real bucket snapshots.

### M2-11 The full snapshot's staged installation (S-06 M2 parts, S-17 latency part; plan §8.6.3, §8.4.3)

- **Code:** `23a56b9` → `ab0f695`:
  - the snapshot chunk;
  - the staged-index port and `LocalSearchIndex.stage`;
  - the installation tables;
  - canonical operations counting as settled for causal readiness;
  - views over the live or a staged canonical table;
  - `SnapshotInstallation` and its outcome.
  - Documented in `docs/SYNC-PROTOCOL.md` §8b.
- **Harness:** `m2/harness-v30/`, 7/7 on its first run.
  - v29's pinned table list predates the three installation tables. **v31** has the updated list, 10/10.
  - v13, v15, v19, v20, v25 and v28 pass again.
- **Cases:**
  - **Under writes, with searches** (the S-06 search cases on unwindowed tasks):
    - A canonical task "Dentist appointment" is edited locally to "Orthodontist…".
    - A snapshot at cut 20 (creation and a note) begins staging. Its first chunk is staged, and Core rejects the edit.
    - Then 20 captures arrive, the rest is staged, passes run, and it installs.
    - Searches matched the view at every point: before the rejection, during staging, after the swap and after a restart. "orthodontist" appeared only while the edit stood. "dentist referral" found the task after the swap, and the 20 captures were found.
    - Cursor 20.
    - **Capture latency:** p95 2.6 ms during staging; the swap took 8.7 ms.
  - **The burst the passes absorb:** 3,000 changes before the first pass. Five passes ran, the backlog at the installation point was 440, and it installed, with all 3,000 found.
  - **Above the threshold:** the same 3,000, plus 600 during each of the five passes. The backlog was 3,440, and the staging was invalidated without applying anything: no cursor, no canonical task, and the 3,000 live captures intact.
  - **The boundary:** a backlog of 2,048 installs, and 2,049 invalidates.
  - **A newer page and an older cut:**
    - A page through 25, installed during staging at cut 20, invalidates (`newerCanonicalPage`), and the live page's note stays.
    - Staging the same cut-20 snapshot again under cursor 25 is refused the same way.
  - **Staging across a restart:** one chunk is staged, then a page `(5,15]` carrying a note that is also in the snapshot is applied, and the installation reports one chunk missing. After a restart, staging continues and installs: the note appears once, at cursor 20.
  - **A chunk with one bit flipped:** refused as not included at its index, and the installation stays incomplete.
- **Full build and R1 suite:** `m2/suite-after-installation-20261124T220211Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS** for these parts.
- **Not yet:**
  - process kills inside each step on real files. A step is one transaction, so these test SQLite's rollback; the restart cases above test the step boundaries.
  - disk exhaustion during an installation, on the container tmpfs, and the peak staging, index and WAL sizes (S-17);
  - the windowed buckets' deferred pages and absence after the swap (S-08).

### M2-12 The staged installation under storage pressure and process kills (S-17 M2 installation parts, S-06 kills; plan §8.15.2, §8.6.3)

- **Code:** `e06c79f` → `177763a`. Writes other than captures (release steps, staging a chunk, building the staged index, a catch-up pass, the installation point) read free space fresh at the start of each bounded transaction. Each stops with `reserveProtected` rather than use the capture reserve.
- **Harnesses (first outcomes kept):**
  - **v32:** never built. Read first, it needed five corrections.
  - **v33:** 3 of 4 host tests passed. The reserve test then installed after staging only two of its four chunks.
  - **v34:** 4/4 on the host. Its tmpfs run stopped at 2,000 captures before the disk was exhausted, so "the capture that doesn't fit" never happened; everything else passed.
  - **v35:** captures until three are refused, 4/4 on the host and 1/1 in the container.
  - v13, v15, v19, v20, v25, v28, v30 and v31 pass again.
- **Cases:**
  - **The reserve, with free space set to the reserve plus 1 KiB:** staging a chunk, a catch-up pass, a staged-index step, the installation point and a release step were all refused with `reserveProtected`. A capture saved meanwhile. With space back, staging finished and installed.
  - **Peak sizes:**
    - Installation: 10 chunks (2,000 tasks with 400-character notes), 50 captures after each chunk.
    - Peaks: database file 6.4 MB, live WAL 4.6 MB, staged tables and indexes 5.4 MB (`dbstat`).
    - The WAL was 0 bytes after the swap's truncating checkpoint, and 2,000 tasks were found.
  - **Real SIGKILLs in a child process** (the harness's runner, started again with a killing indexer):
    - inside the staging-index transaction;
    - inside the swap transaction, while it applied its backlog.
    - **After each:** the reopened replica had no cursor, the old capture searchable and nothing of the snapshot, so the old view survived. The staging was intact: the installation completed (cursor 100, 10 tasks found), and `integrity_check` was ok.
  - **Storage filling during a staged installation, inside the pinned container:**
    - **Setup:** `swift:6.4.2-trixie`, `sha256:9733821c…430097`, a 48 MiB tmpfs, no network, the rootful engine. Script `m2/container-20261124T2100Z/run-s17-v3.sh`, run `run-20261124T220823Z`.
    - **What happened:** another writer left room for only part of a 15-chunk snapshot (3,000 tasks).
      - Staging stopped at the reserve after 5 chunks.
      - 2,848 captures were then saved. The ballast was used, and the next three were reported not saved.
      - After space returned, the database was consistent, every saved capture was present, staging resumed, and the installation completed with 3,000 tasks found.
    - **Earlier runs:** v34's run `run-20261124T220735Z` stopped at 2,000 captures, as recorded above.
- **Full build and R1 suite:** `m2/suite-after-reserve-checks-20261124T221039Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**
- **Not run:** `max_page_count` on "the Fedora host" (plan §8.15.2) is `NOT_RUN_ENVIRONMENT`, because the platform is Debian 13. The in-database `SQLITE_FULL` case ran in M2-3.

### M2-13 Calendar buckets on the replica: memberships, the absence rule, repairs and rolling windows (S-08 replica part; plan §8.4.2, §8.4.3, §8.3.5)

- **Code:**
  - LisaSyncProtocol, `e1309be` → `737477b`: `OccurrenceRow`, `CalendarBuckets`, `DerivedRecord`, and `ChangeEntry` with the record form.
  - LisaReplicaStore, `ea589e2` → `e838a98`: `derived_rows`, `DerivedRows`, record entries in pages, `OccurrenceListing`, `CalendarBucketStore`.
  - Documented in `docs/SYNC-PROTOCOL.md` §8a.
- **Harness:** `m2/harness-v36/`, 6/6 on its first run.
  - v31's pinned table list predates `derived_rows`. **v37** has the updated list, 10/10.
  - v13, v15, v19, v20, v25, v28, v30 and v35 pass again.
- **Cases (each one of the plan's §8.4.2 acceptance cases):**
  - **Bucket ranges:**
    - 2026-11-24 maps to the right day; 1969-12-31 is −1, and instant −1 ms is in bucket −1.
    - A one-hour event, an event crossing midnight, an event ending exactly at midnight, and a zero-length event each fall in the buckets R1's overlap rule gives.
    - An all-day event on 2026-11-24 covers buckets day − 1 through day + 1.
  - **Absence in both orders, with what a replica shows from an older proof:**
    - Setup: an event spans buckets A and B, delivered at 105, and both are proved through 110. Both are repaired.
    - (1) A's snapshot at 150, without the event, is published first, then B's delayed snapshot at 120, which still holds it. (2) The reverse order.
    - **From A's publication on, in both orders:** A never lists the event. B lists it as of 120, proved there.
    - **Before A's publication:** A showed it as of 110, from its older proof.
    - **Final cursors:** A = 150, B = 120.
  - **Windows that don't nest:**
    - Setup: a replica covering days 30–90 receives a page listing days 1–60, with a deletion on day 40 and nothing on day 45.
    - Day 40's event is gone; day 45 advances on the empty proof; days 30–60 move to 20.
    - Days 61–90 stay at 10, with day 70's event still listed. Days 1–29 are not covered: `gap(nil)`.
  - **A rolling window:**
    - An event spanning days 29–31 stays when day 29 is dropped, and counts on day 30.
    - When it moves to days 33–34, the entry names the old range too, so days 30 and 31 stop listing it, and 33 and 34 list it.
    - Dropping every bucket it overlaps drops the row.
  - **A page during a bucket repair:**
    - Setup: day 31 is repairing when a page `(120,150]` for days 31 and 32 arrives.
    - Day 31 defers it, and day 32 reports a gap at 100. Fetched again from 100, day 32 reaches 150.
    - Publishing day 31's snapshot at cut 120 applies the deferred page, ending at 150, never at 120. Both days list the event.
  - **A stale relayed page `(90,120]` for A (cursor 150) and B (cursor 100):**
    - A ignores it. B applies `(100,120]`: the entry at 95 is trimmed, and B moves to 120.
    - The row, updated at 130 through A, keeps its 130 value in both buckets. In B it counts as not yet proved there.
- **Full build and R1 suite:** `m2/suite-after-calendar-buckets-20261124T222022Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**
- **Still to come for S-08's replica part:**
  - the planning-zone cases: floating and unknown-zone rows marked unverified until authoritative proof; all-day rows read in the planning zone; the Nuuk gap; retained civil inputs;
  - the overlay watermark and constant-size publication;
  - readers before, during and after a repair (see one view or the other);
  - derived records in full snapshots;
  - searches scoped to days.

### M2-14 Partition repairs by generation: the overlay watermark and constant-size publication (S-08 replica part; plan §8.4.3)

- **Code:** `07bd0b9` → `799a16f`:
  - derived rows and memberships by generation, each partition's published generation, and repair records with their chunks;
  - the watermark advancing with every local change;
  - the repair steps: record, stage, publish, deferred pages, clean up;
  - M2-13's one-call `finishRepair` now running on them.
  - Documented in `docs/SYNC-PROTOCOL.md` §8a.
- **Harness:** `m2/harness-v39/`, 5/5.
  - **v38:** didn't compile; three catches of untyped helpers. It is kept unchanged.
  - **v36 and v28:** pass again (6/6 each) on the new path, so M2-13's cases hold with publication by generation.
  - **v37:** its pinned table list predates the repair tables. **v40** has the updated list, 10/10.
  - v13, v15, v19, v20, v25, v30 and v35 pass again.
- **Cases:**
  - **Staged rows stay invisible until the flip:**
    - A bucket proved at 110 lists "Standup".
    - A repair at cut 200 stages "Standup, moved" and a new "Review". Until publication the bucket still lists only "Standup", as of 110, marked repairing.
    - Three local changes during the repair keep its watermark current, so publication's re-check passes.
    - After publication the bucket lists both new rows as of 200, and the cursor is 200.
  - **Publication is constant in size:** 0.67 ms with 10 staged rows, and 1.19 ms with 5,000. Each bucket then lists all of its staged rows.
  - **Refusals:** a snapshot at cut 200 for a bucket at 300 is refused as stale. A snapshot from another epoch abandons the repair. The bucket stays unrepaired.
  - **A bucket entering the window:**
    - It starts at cursor 0.
    - With one of its two chunks staged, publication reports one missing (`repairIncomplete(1)`).
    - With both staged, it publishes 600 rows at cut 700.
  - **Cleanup:** after two successive repairs of one bucket, three membership records exist. Cleanup in chunks of 1 leaves only the published generation's one, with the listing unchanged.
- **Full build and R1 suite:** `m2/suite-after-repair-generations-20261124T222922Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**
- **What the watermark covers so far:** derived occurrences have no local overlay or search entries yet, so a local change keeps a staged repair current just by advancing its watermark. When event-attached notes and their search entries arrive, the same transaction recomputes them for every staged generation holding the row (§8.4.3 step 3).
