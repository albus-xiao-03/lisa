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
- **Produced later, at M3's start (M3-0):** a raw `sending` file left by a killed process, R1's recovery of it in a separate copy, and the before/after pair of completed-entry pruning.
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
| S-06 | Snapshot installation under writes | M2 | M2 parts run (M2-11): installation under writes with searches, the backlog cases and boundary, a newer page and an older cut, restarts between steps, tampered and incomplete snapshots; kills inside the staging and swap transactions (M2-12), derived records with absence after the swap and a page during staging reflected once (M2-16): the M2 part complete |
| S-07 | Pieces, value limits, reviewed-set artifacts | M2, M3, M5 | Not run |
| S-08 | Interval coverage and the planning-zone change | M2, M3, M6 | M2 parts run (M2-10, M2-13, M2-14): the cursor cases, deferral, the absence rule in both orders, non-nesting windows, rolling windows and moves, stale relayed pages, repairs by generation with the overlay watermark and constant-size publication, zone-unverified floating rows and all-day rows read in the planning zone (M2-15): the M2 replica part complete; Core's zone generations and re-expansion (M3) and the simulated link (M6) to come |
| S-09 | Backup lineage, anchors and discovery | M3 | Not run |
| S-10 | Re-anchoring, restore, fences and admission | M3 | Not run |
| S-11 | Delivery holds after a restore; (l) recorded against KF-1 | M3, M4, M8 | Not run |
| S-12 | Reminder firings and OS ownership; (m) recorded against KF-2 | M8, X6 | Not run |
| S-13 | Export, rollback and installation of either v4 database | M5, M9, X3, X7 | Not run |
| S-14 | The destination policy at every redirect | M7, X1, X5 | Not run |
| S-15 | VPN publishing | M4, target host | Not run |
| S-16 | Size boundaries and bounded dependency release | M1, M3, M6 | M1 part PASS (M1-1, M1-7: budgets, frame header); replica parts run in M2: causal readiness and bounded release (M2-2), the persisted release with nested fan-out and a restart (M2-6), a kill inside a release step (M2-17); M3 and M6 parts not run |
| S-17 | SQLite readers, exhaustion and bursts | M2, M3 | M2 parts run: the single-writer guard (M2-0), `SQLITE_FULL` in a save (M2-3), the reader monitor, the pinned reader and the burst on a container tmpfs (M2-4), storage filling during a staged installation on the tmpfs and the peak sizes (M2-12), kills right after a reported save and inside an unreported one (M2-17); `max_page_count` on the Fedora host `NOT_RUN_ENVIRONMENT`; Core's part at M3 |
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
- **X1, first attempt (the owner, reported 2026-11-26T00:34Z): `FAIL` at the first Xcode build of `LisaProof`.**
  - **The report:** Xcode reported "Failed to produce diagnostic for expression; please submit a bug report" at `Apps/Proof/Nearby/ProofNearbyController.swift:130`. It came in the Claude session, with no harness export. The Xcode version, destinations, commit and any other errors weren't stated.
  - **The expression at line 130:** Design A's PSK selection probe. A closure with no written types sits in a `? :` branch, holding a nested `@MainActor` `Task` and `hintBytes.map(String.init) ?? "none"`. Its types agree with `DesignAParameters.make`, but the type checker found no solution and named no error.
  - **Why the Linux check missed it:** this file imports `Network`, so it was among the 31 files checked for syntax only. X1 was its first type-check.
  - **Status:**
    - `OV-APPLE-X1-01`–`03` (E-2) can't pass until a fixed build passes.
    - The nearby cells (N-1), the fetch probe (E-1) and test plan `X1` weren't reached.
    - N-1, E-1 and E-2 stay open.
  - **Evidence:** `.tmp/r2/20261124-r2-5462/owner/x1-attempt1-20261126T0034Z-v2.md` (the verbatim report, the analysis and the proposed fix; not applied, since the owner said this was not a resume).
  - **Next, on resume:** the fix, a Linux type-check of the Apple-importing files against stand-ins, then a new X1 request naming the fixed commit (`R2-CHECKPOINT.md` §6).

### M1-8b X1 attempt 2: the fix, and the Linux type-check of the whole `LisaProof` target (2026-11-26; `docs/DECISIONS.md` D-70)

- **Reproduced on Linux:**
  - **Minimal copy:** the expression, in a main-actor class, fails on Swift 6.4.2 and 6.4.3 with the same "failed to produce diagnostic" at the `?` (`x1/repro-v1/`).
  - **Variants (6.4.2):** fourteen locate the cause. An untyped closure as a branch of `? :` isn't inferred `@Sendable` from the declared type. Without a capture list, Swift reports "cannot convert value of type '(Int?) -> Task<(), Never>' to specified type '(@Sendable (Int?) -> Void)?'". With `[weak self]`, it fails to produce that diagnostic. An explicit `@Sendable`, explicit types or an `if` assignment each compile.
- **The fix** (`f03cf24`): the probe closure is written `@Sendable` with typed parameters and assigned in an `if`.
- **The hedge** (`0528fc3`–`795b4f3`): the three `Binding(get:set:)` closures became key-path bindings through subscripts on `ProofModel`. They compile whether or not the SDK declares those closures `@Sendable`, which can't be confirmed offline.
- **The type-check** (`x1/typecheck-v1/`, `run-v1.sh`):
  - **What it compiles:** all 69 files as the one module `LisaProof`, in Swift 6 mode, `-parse-as-library`.
  - **Real modules:** `LisaCrypto`, `LisaSyncProtocol`, `LisaTrust` and `LisaHTTP`, built from HEAD (`x1/scratch-v1`), and the toolchain's Observation with its macro.
  - **Stand-ins:** for Network, Security, dnssd, CryptoKit (re-exporting swift-crypto), SwiftUI, UIKit, CoreImage with `CIFilterBuiltins`, CoreGraphics and Darwin (`stubs-src/`).
  - **Passes:**
    - iOS-like: UIKit present.
    - macOS-like: no UIKit, and `ProofDeviceFacts.swift` copied with `os(macOS)` true.
    - A baseline: HEAD's unfixed controller.
- **Results**, final sources, Swift 6.4.2 and 6.4.3 (`run-20261126T012602Z-6.4.2`, `run-20261126T012627Z-6.4.3`):
  - iOS-like and macOS-like passes: 0 errors, 0 warnings.
  - The baseline: exactly one error, X1 attempt 1's, at line 130:17.
  - `swift format lint` on the changed files: clean.
  - The first run's two warnings came from the dnssd stand-in, which lacked C's `@discardableResult`; v2 adds it.
- **Negative controls** (`negative-controls-v2.sh`, `negative-20261126T012458Z/`): six of six caught. A misspelled member in a SwiftUI body and a wrong key-path key type are caught. So are a wrong `NWConnection` label, a var mutated inside a `@Sendable` handler, and a main-actor call outside `MainActor.assumeIsolated`. So is a `[weak …]` closure in `? :`, which fails to produce a diagnostic. v1's run of the last control named a missing file and is void.
- **Not shown:** an Apple build. The stand-ins carry Claude's knowledge of the SDK: whether Network's classes are Sendable and its handlers `@Sendable` (both assumed), and the Security blocks (not assumed). Xcode's Swift may be older than 6.4. Evidence: `x1/typecheck-v1/RESULT.md`.
- **Result:** ready for X1 attempt 2 (owner-run) at `795b4f3` or later.

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

### M2-15 The planning zone on the replica: zone-unverified floating rows and all-day rows in the planning zone (S-08 replica part; plan §8.4.2)

- **Code:**
  - LisaSyncProtocol, `38410d9` → `fff21bd`: `ZoneProof`; on `OccurrenceRow`, the `unknown` zone class, the expansion zone and civil inputs; zone proofs as derived records.
  - LisaReplicaStore, `e3c987b` → `c5b5cb1`: the schema columns and `unverified_sources`, derived rows storing source and zone, `PlanningDayView`, `PlanningZone`.
  - Documented in `docs/SYNC-PROTOCOL.md` §8a.
- **Harnesses (first outcomes kept):**
  - **v41:** 3 of 4. One expectation placed a UTC event at 23:30Z on the 24th on the wrong local day at UTC−12, where it is 11:30 on the 24th. The product was right.
  - **v42:** the corrected test, but its manifest's header comment broke the manifest.
  - **v43:** the corrected test under a valid manifest, 4/4.
  - **v40:** its pinned table list predates `unverified_sources`. **v44** has the updated list, 10/10.
  - v13, v15, v19, v20, v25, v30, v35, v36 and v39 pass again.
- **Cases:**
  - **All-day rows and a UTC call:**
    - An all-day holiday on 2026-11-24 is on the 24th at both UTC+14 and UTC−12, and on no 25th.
    - A UTC call at 23:30Z on the 24th falls on the 24th at UTC−12 and on the 25th at UTC+14.
    - Free time is offered on both verified days.
  - **A zone change, New York to Berlin:**
    - **Before:** a floating lunch expanded in New York, a UTC call and an all-day holiday make a verified day.
    - **After the change:** only the lunch is unverified, its source is marked, and no free time is offered.
    - **Core's re-expansion arrives:** the lunch, re-expanded for Berlin, is verified on its own. Its source stays unverified, so still no free time.
    - **A zone proof arrives** (`calendar:personal`, Europe/Berlin, the window's buckets): everything is verified and free time returns.
  - **A migrated row without civil inputs**, beside one that kept them: after a change from America/Nuuk to UTC, both days its source could move into offer no free time, and the retained civil start is available to show.
  - **No free time** on a day whose bucket is repairing, or on an uncovered day.
- **Full build and R1 suite:** `m2/suite-after-planning-zone-20261124T223742Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**
- **What M2's replica part of S-08 now covers:** deferral, the overlay watermark and constant-size publication, absence in both orders with what an older proof shows, zone-unverified floating rows, and all-day rows read in the planning zone, as plan §9's M2 row lists.
- **Later milestones:**
  - Core's zone generations and re-expansion from retained civil inputs, including the Nuuk floating event and the interior DST day (M3);
  - the simulated link (M6).

### M2-16 Derived records across a full snapshot's swap (S-06's last M2 case; plan §8.6.3 "Pages and absence across the swap")

- **Code:** the last commit of `SnapshotInstallation.swift`. Full snapshots stage derived rows and membership records and swap them in with the canonical tables. Every covered bucket reads the snapshot's memberships from the first reader on, and the swap overtakes any bucket repairs.
- **Harness:** `m2/harness-v46/`, 2/2. v45 didn't compile (an untried closure in an expectation) and is kept unchanged. v13, v15, v19, v20, v25, v30, v35, v36, v39, v43 and v44 pass again.
- **Cases:**
  - **Absence from the first reader on:** an event spans buckets A and B at 105, and a full snapshot at 150 holds it moved to B only.
    - Right after the swap, A lists nothing, and B lists the moved event, proved there at 150.
    - Delayed older snapshots of either bucket at 120, still holding the event in both, are refused as stale.
    - The event never returns to A.
  - **A page during staging:** an occurrence delivered by a page while a full snapshot that also holds it was staging is listed exactly once after the swap, at cursor 150.
- **Full build and R1 suite:** `m2/suite-after-full-snapshot-records-20261124T224312Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.** S-06's M2 part is complete.

### M2-17 Process kills right after a reported save and inside steps (R2-L03; S-16 and S-17 replica parts; plan §8.6.1, §8.2.2, §8.4.2)

- **Code:** none changed. This case runs the kills that M2-3, M2-6 and M2-11 left for later.
- **Harness:** `m2/harness-v47/`, 6/6 on its first run (log `m2/harness-v47-test-20261124T230642Z.log`).
  - Every kill is a real SIGKILL of a child process: the harness's runner, started again in a kill mode.
  - A kill inside a transaction comes from an indexer that the store calls inside it.
  - **Build:** this is the first harness built with the shared scratch path `m2/harness-scratch-late` (427 MB once, instead of about 400 MB a harness). The project volume had 1.2 GB free.
  - **Deviation:** its test file was edited in place once before its first build (a `World` value moved into each test). The plan's run-directory rule and the standing temporary-file rule call for a new version instead. The text before the edit exists only in the session transcript.
- **Cases:**
  - **R2-L03, a reported save:** the child saves, writes the reported result to a file, and SIGKILLs itself at once. After a restart:
    - **One signed save, and a burst of 50:** every reported operation is in the journal, pending and local, as an overlay. Its signed bytes verify with the device key, and its origin triple is the reported one. The task is in the view and found by search, its submit follow-up is queued, and the generation is at least the reported one.
    - The next launch is a new incarnation linked to (I1, last reported sequence). Its first save takes sequence 1, and no origin triple repeats.
  - **R2-L03, a reported draft** (the key unavailable): after the kill the draft is held with its original input, in the view, found by search, with its sign-draft follow-up and no journal entry. Once the key is back, it is signed under its own operation ID and verifies.
  - **"Saved" only after commit (§8.6.1):** the child is killed inside its second save's transaction, before that save reported. After a restart only the first save exists: the journal, generation, follow-ups and index hold nothing of the second, and I1's last sequence is 1.
  - **Inside a causal release step (§8.2.2 "a crash loses nothing"):** 300 waiting notes depend on a task's creation.
    - The child releases the creation, then is killed inside the next release step.
    - After a restart the view has the task with no notes. The drain resumes from the tables, releases all 300 exactly once, and leaves no waiting, ready or marker rows.
  - **Inside a change page's application (§8.4.2):** the child is killed inside the transaction applying a page (0, 10] with a creation and an edit. After a restart the cursor and the view are as before. The same page then applies (cursor 10, 2 entries) and, sent again, is ignored.
  - `integrity_check` was ok after every kill.
- **Result: PASS.**

### M2-18 A revocation learned after provisional peer application (R2-L17, replica part; plan §8.1.3, §8.6.1, §8.2.2)

- **Code:** in LisaReplicaStore: a `revoked` journal state, the `revocations` table (schema v1's 27th), `recordRevocation`, `revocations()` and `ReplicaRevocation`, `RevocationTables`. `receive` stores a revoked device's new operations as `storedRevoked`. The view leaves revoked entries out, and a final receipt can still authorize them. `docs/SYNC-PROTOCOL.md` §8c.
- **Harness:** `m2/harness-v48/`, 6/6 on its first run. `m2/harness-v49/` is v44 with the table list naming `revocations`, 10/10. v44 now fails by design and is kept unchanged.
  - v13, v15, v19, v20, v25, v28, v30, v35, v36, v39, v43, v46 and v47 pass again. Each rebuilt in its own `.build` directory, which together took about 200 MB; the volume then had 889 MB free.
- **Cases:**
  - **Pending effects leave the view at once:**
    - **Setup:** a trusted peer created a trip, and the peer to be revoked created an errand with a note and renamed the trip. The trusted peer added a note to the errand. All of these were applied provisionally and found by search.
    - **The revocation:**
      - It revoked exactly the revoked peer's three operations, in one local change of kind `revocation`, naming both tasks. The generation advanced by one.
      - The trip's title is the trusted peer's again.
      - The errand's creation is gone (`exists` false), and only the trusted peer's note remains. Search finds nothing of the revoked peer.
      - The three entries are `revoked`, no longer overlays, and their exact bytes still verify. The trusted peer's entries are still pending.
    - **Permanent:** recording the same revocation again changes nothing, the generation included, and a second revocation for the device at another position is kept beside the first.
  - **Core-accepted work stays:**
    - An operation with a final Core receipt, and one committed through a page, keep their effects.
    - Only the unreceipted note is revoked.
  - **A waiting operation:** the revoked peer's edit was waiting for a missing dependency, and a trusted note waited for that edit.
    - The revocation decided the edit, and the note was then released with the edit ignored.
    - No waiting, ready or marker rows were left.
  - **Later arrivals:**
    - The revoked device's new operation is `storedRevoked`, outside the view and the queues. Sent again, it is a `duplicate` in state `revoked`.
    - An operation that depends on it is not held back.
    - After a restart the revocation still applies.
  - **Core still decides:**
    - Core's acceptance of a revoked note that had entered the view brings it back as an overlay, found by search.
    - A provisional receipt for another revoked note changes nothing.
    - A note revoked while waiting, then accepted, appears only with the canonical page that contains it.
  - **This replica's own device:** the revocation is recorded, and the saved capture stays pending, in the view and found by search.
- **Full build and R1 suite:** `m2/suite-after-revocations-20261124T231238Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**

### M2-19 Peer custody kept apart from Core commitment (R2-L15 replica part, R2-SYNC-04; plan §8.6.1, §8.7)

- **Code:**
  - `CustodyAcknowledgement` and `SignedCustodyAcknowledgement` (LisaSyncProtocol).
  - The `lisa-r2-custody-v1\n` domain and `CustodySigning` (LisaTrust).
  - `recordCustody`, `custody(of:)`, `safety(of:)` and `OperationSafety`, with two error cases (LisaReplicaStore).
  - `docs/SYNC-PROTOCOL.md` §4 and §8c.
- **Harness:** `m2/harness-v50/`, 4/4 on its first run.
- **Regression package v1** (`m2/make-regressions-v1.py`, run `m2/regressions-run-20261124T232437Z/`):
  - **Method:** the current harnesses' test targets, copied byte-identically, in one package against the working tree. It is built once in the shared scratch path without the index store, and each target is run alone.
  - **Results:** 18 targets pass again with their usual counts: v6, v9, v10, v13, v15, v19, v20, v25, v26, v28, v30, v36, v39, v43, v46, v48, v49 and v50. v35 and v47 each start their runner again with a child filter, so they ran in their own packages, and both pass.
  - **Disk:** switching the shared scratch path's index setting rebuilt it, and the volume fell to 349 MB free. Superseded build output from before this run was then removed from `.build/` (`m2/disk-reclaim-20261124T232752Z.txt`, 7.1 GB), leaving 7.5 GB.
- **Cases:**
  - **Kept apart:** a local capture acknowledged by two peers.
    - Each acknowledgement is recorded once.
    - The entry stays pending and an overlay, with no receipt and no position, and its submit follow-up stays queued.
    - `safety` reports saved here, held by both peers, and not synced with Core.
    - Only Core's receipt makes it synced (epoch and position 12), with both holders still listed. Both survive a restart.
  - **Only verified custody of the exact bytes counts.** Each of these is refused, and none changes anything:
    - another device's signature over the holder's name (`invalidSignature`);
    - a holder outside the roster (`unknownHolder`);
    - another dataset;
    - a malformed body;
    - other bytes than the journal's;
    - an unknown operation;
    - this device's own acknowledgement;
    - a device revoked meanwhile.
  - **A relayed operation:** a peer holding another peer's relayed operation is custody only. The journal reports no safety for an operation it doesn't hold.
  - **Wire form:** the vector of §8c, decoded back to the same value. An unknown field and a negative time are refused.
- **Not on the replica yet:** Core's receipt format and its signature check (M3), and the relay over the nearby link (M6). The store records receipts the sync engine has verified.
- **Full build and R1 suite:** `m2/suite-after-custody-20261124T232155Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**

### M2-20 The duplicate rules against canonical state, clock skew and an old device's replay (R2-SYNC-02; R2-L35 and R2-L10 replica parts; plan §8.2.1, §8.3, §8.6.1)

- **Found while writing this case:** the replica checked the duplicate rules against its journal only.
  - A relayed copy of an operation it knew only from canonical state, from a page or a full snapshot, was stored as a new pending journal entry and listed as an overlay.
  - A changed body under such an operation's ID, or its origin triple under another ID, raised no security event. The second could even enter the view provisionally.
  - §8.2.1 requires the rules on every replica with no exception.
- **Code (fix):**
  - Canonical operations keep their origin triple, with an index, in both the live and the staged table (`ReplicaSchema`, `SnapshotInstallation`, `CanonicalTables`).
  - The lookups by ID and by triple consult canonical state after the journal (`OperationJournal`).
  - `receive` returns a canonical-only duplicate in Core's state (`ReplicaStore`).
  - `docs/SYNC-PROTOCOL.md` §8.
- **Harness:** `m2/harness-v51/`, 4/4 on its first run, in the shared scratch path without the index store.
  - Regression package v2 is v1 plus v51 (`m2/make-regressions-v2.py`, run `m2/regressions-run-20261124T233307Z/`). All 19 targets pass with their usual counts, and so do v35 and v47 in their own packages.
- **Cases:**
  - **The duplicate rules against canonical state:**
    - An operation known from a page and relayed again is `duplicate` in state `accepted`. No journal entry and no overlay appear.
    - Its ID under another body is `identity_reuse`, and its triple under another ID is `sequence_reuse`. Each security event names the canonical operation and its digest.
    - After a full snapshot's swap, a relayed copy of a snapshot operation is a `duplicate`, and its triple under another ID is `sequence_reuse`: the staged table carried the triples.
  - **R2-L35, skewed creation times:**
    - Two concurrent title edits keep both candidates in four runs: either device's clock a day fast or a month slow, and either arrival order.
    - An edit that observed both wins, though its clock says it was made a year earlier, and it arrived first.
  - **R2-L35, a wall-clock step:** the replica's clock stepped back a day, then ahead a year, between three local saves.
    - Generations and sequences 1, 2, 3 follow the saves, and the envelopes carry the clock's times as given.
    - The last edit stands, and another replica receiving the three in reverse order shows the same.
    - The monotonic clock for timeouts and budgets is M2-9's, and the planning zone change is M2-15's.
  - **R2-L10, an old device's replay:** Core's pages committed a task, a note and then the deletion. An old device that had been offline then:
    - sent the edit and the note it made before the deletion, which stay superseded;
    - replayed the creation and the note, which are `duplicate`;
    - created the same item again, which stays deleted.
    - Search finds nothing, also after a restart.
- **Full build and R1 suite:** `m2/suite-after-canonical-duplicates-20261124T232956Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Result: PASS.**

### M2 boundary (run `20261124-r2-5462`, final: a clean reconstruction of the M2 head `815bbbc`)

- **Tree:** `m2/clean-20261124T233606Z/tree`, rebuilt from `815bbbcf3dda1a32355b897ed6de6f86fa3408d5` with `git show` and checked byte for byte against `git rev-parse` (`m1/reconstruct-commit.py`): 1171 files of 815bbbcf3dda1a32355b897ed6de6f86fa3408d5, all byte-exact; manifest sha256 28e1587314e8dcb4c18931e4c78d13e7bcca7533f6ca3ad50fd0750134e0af9f.
- **Toolchain:** Swift 6.4.2 (swift-6.4.2-RELEASE), x86_64 Debian 13 sandbox.
- **Builds:** debug with tests 0 warnings, release 0 warnings, both exit 0.
- **R1 suite** (unmodified): 376 tests in 66 suites passed. The runner's SHA-256 is `cd411543f1ec2107…`; it differs from the working tree's because the path differs.
- **Fixtures:** `lisa-verify run --mode fixture`, 9 PASS (report `run-20261124T233727Z-2v5yso`).
- **Lint:** `swift format lint -r Sources Tests Harness Apps Package.swift`. The one finding is R1's `Package.swift:172` (AddLines), unchanged since M0.
- **Harnesses:** every current M2 harness against the clean tree, 108 tests in all, each target run alone (`make-harnesses.py`, sources byte-identical, `harnesses.manifest.tsv`). All of them passed:
  - v6 WALGuardTests: 4 tests in 1 suite.
  - v9 MergeTests: 7 tests in 2 suites.
  - v10 CausalTests: 4 tests in 1 suite.
  - v49 ReplicaStoreTests: 10 tests in 2 suites.
  - v13 StorageTests: 5 tests in 2 suites.
  - v15 TaskMergeTests: 7 tests in 2 suites.
  - v19 EffectiveViewTests: 4 tests in 1 suite.
  - v20 LocalSearchTests: 3 tests in 1 suite.
  - v25 ResolutionTests: 6 tests in 2 suites.
  - v26 MonotonicClockTests: 3 tests in 1 suite.
  - v28 ChangePageTests: 6 tests in 1 suite.
  - v30 InstallationTests: 7 tests in 1 suite.
  - v36 CalendarBucketTests: 6 tests in 1 suite.
  - v39 BucketRepairTests: 5 tests in 1 suite.
  - v43 PlanningZoneTests: 4 tests in 1 suite.
  - v46 FullSnapshotRecordTests: 2 tests in 1 suite.
  - v48 RevocationTests: 6 tests in 1 suite.
  - v50 CustodyTests: 4 tests in 1 suite.
  - v51 SkewReplayTests: 4 tests in 1 suite.
  - v35 own package: 5 tests in 2 suites.
  - v47 own package: 6 tests in 2 suites.
  - Packaging: nineteen ran in one package; v35 and v47 ran in their own packages, because their kill tests start the runner again with a child filter that matches both. All built in one scratch path without the index store.
  - Superseded harnesses are kept unchanged and were not run: v12, v16, v17, v21, v24, v27, v29, v31, v33, v34, v37, v40, v41 and v44. Others never built or didn't compile: v7, v8, v11, v14, v18, v22, v23, v32, v38, v42 and v45.
- **Disk** (free on the project volume): 7.6 GB at the start; 5.1 GB after the debug build; 4.3 GB after the harness build; 4.1 GB after the harness runs; 2.2 GB (96% used) after the release build. The clean run's build output stays in the run directory (plan §10.2).
- **Interim boundary:** an earlier clean run on `642e955` (`m2/clean-20261124T225253Z/`, before M2-17 to M2-20) passed the same steps with 17 harnesses.
- **Result: PASS.** The M2 milestone's builds, suite, fixtures, lint and harnesses pass on the clean M2 head.

## 2c. M3 (run `20261124-r2-5462`)

### M3-0 The deferred frozen R1 queue fixtures (plan §8.18 step 3; M0-5's remainder, due before S-01)

- **Harness:** `m0/frozen-client/harness4/`, built as new files by `make-harness4.py`. It is harness3, kept unchanged, plus `Cases+M3.swift`.
  - `generate-m3` runs only the new cases.
  - The internal `sending-child` mode is the process case 26 kills.
  - The scripted host's block-until-killed announcement is written unbuffered.
  - It links R1's `LisaClient` and `LisaAPIContract` from the byte-exact R1 tree `m0/r1-src` (491c90a).
  - Sources: `harness4-SOURCES.sha256`.
- **Build:** `build5.sh`, offline as M0's: file:// mirrors, a dead proxy, its own SwiftPM cache directories. Debug and release exit 0, 0 warnings. R1's lockfile stayed `9608e8e0…37494`. `frozen-client-harness` release `301582bbfdc9608a…`, debug `e94521096d662435…`.
- **Run:** the release binary, `generate-m3 --queues … --transcripts …` with no proxy variables set, into `m0/frozen-client/m3-fixtures-20261125T012812Z/`. Four cases PASS. `queues/MANIFEST.tsv` and `CASES-SCRIPTS.md` come from `tools/manifest.py`, and `SHA256SUMS` covers the outputs.
  - A second run into `m3-fixtures-20261125T012831Z/` produced the four queue files byte-identical (fixed request IDs, injected clock).
- **Cases.** Every file is written by R1's own `OfflineQueue` and `FileQueueStorage`, mode 0600:
  - **26 `sending-killed-raw`:** the child enqueued an idea capture at +0 s and flushed at +60 s against a host that never answers.
    - R1 saved the entry as `sending` before it called the transport (`OfflineQueue+Flush.swift:88-91`). The child announced the request ID from inside the transport and was killed there with SIGKILL.
    - The file holds one entry: `sending`, attempts 1, lastAttemptAt +60 s, with no uncertainty, completion, response or error, and no staging directory beside it.
    - SHA-256 `ac020818bef133f1…`.
  - **27 `sending-killed-recovered`:** case 26's file copied byte for byte and opened with R1's `OfflineQueue` (`OfflineQueue.swift:30-50`).
    - The entry is `pending` with its request ID, uncertain since its last attempt (+60 s), and R1 saved the queue.
    - Case 26's file is unchanged.
    - `feb9d1f0b8bf9bea…`.
  - **29 `prune-completed-before`:** a link capture applied at +61 s (201, R1's CaptureDTO kept as the response). At +3,660 s, one second before `completedRetention` (3,600 s) ends, an idea capture is queued and the applied entry stays. `f603e3916635d35f…`.
  - **30 `prune-completed-after`:** case 29's file copied. At +3,661 s the next enqueue prunes the applied entry (`OfflineQueue.swift:188-193`), and only the two pending entries remain. `944b5c5bcfdc38ec…`.
- **Result: PASS.** The M0 frozen artifacts S-01 needs are complete. The remaining frozen datasets (`acceptedByProvider`, `confirmedDelivered` and the others listed in M0-6) are due before S-02 and S-13 at M9.

### M3-1 Schema v5 and the Core ledger's intake (R2-SYNC-02, -03; R2-L14 lookup, R2-L06 and R2-L11 at Core; plan §8.4.1, §8.2.1, §8.2.2, §8.3.4)

- **Code:**
  - `CoreReceipt` and `SignedCoreReceipt` (LisaSyncProtocol).
  - The `lisa-r2-receipt-v1\n` domain and `ReceiptSigning` (LisaTrust).
  - In LisaStore: migration 5 (the ledger tables), and `ledgerWrite`/`ledgerRead` on R1's record store.
  - The new LisaCoreLedger: `CoreLedger`, `CoreCausalTables`, `CoreOperationRecords`, `CoreTaskFold`, `TaskProjection`, `R1Identity` and two support files.
  - `docs/DECISIONS.md` D-58 and D-59; `docs/SYNC-PROTOCOL.md` §8d.
- **First failure and fix:** the first R1 suite run with migration 5 failed 3 issues (`L23FailedMigrationTests`). R1's test snapshots every table in rowid order, and two new tables were `WITHOUT ROWID`. They became ordinary tables before any commit, and no R1 test changed.
- **Full build and R1 suite:**
  - `m3/suite-after-core-ledger-20261125T014155Z/`: debug build 0 warnings; the suite failed 3 issues, as above.
  - `m3/suite-after-core-ledger-rowid-20261125T014236Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Harness:** `m3/harness-v2/`, 8/8 on its first run. v1 didn't compile (a `try` on the right of `&&` inside an expectation) and is kept unchanged.
  - **Regression package v4** (`m2/make-regressions-v4.py`, run `m2/regressions-run-20261125T014819Z/`): v2's 19 targets plus this one. All 20 pass with their usual counts, and so do v35 and v47 in their own packages. `make-regressions-v3.py` was never run: its M3 label held a slash the runner can't use in paths.
- **Cases:**
  - **Intake and the projection:** a creation (high priority, a date deadline, 90 minutes), a rename, a note and a completion.
    - Each is decided in order with a Core-signed final receipt at positions 1–4. Each receipt is retrievable by lookup, verifies by Core's key, and names its operation's digest.
    - R1's `tasks` record shows the rename, the note, priority high, the deadline, 90 minutes, completed with `completedAt`, origin manual, owner-corrected title.
    - `changeSequence` is 1: only the completion was material. The record's ID spells the entity ID as a UUID.
  - **The duplicate rules at Core:**
    - A duplicate returns the original receipt.
    - The same ID with another body is `identity_reuse`, and the same triple under another ID is `sequence_reuse`. Both are recorded as security events naming the stored operation and its digest.
    - A device outside the roster and another dataset are refused before anything is stored. The position stays 1.
  - **Waiting and release:**
    - An edit waiting for its creation gets a provisional receipt naming the creation, with no position. A retry gets the same receipt.
    - 600 more waiting notes; then the creation arrives (position 1).
    - Release steps read at most 256 edges and release at most 256 operations each. All 601 were released exactly once, with final receipts, and no waiting, ready or marker rows were left. The rename wins and the 600 notes are kept; the last position is 602.
  - **Rejections:** an edit of an item Core never held (`unknown_item`, position 2), a note on an idea (`unsupported_operation`), and both members of a forged cycle (`dependency_cycle`).
    - The tasks page lists the decisions at 1, 2, 4 and 5 as accepted, rejected, rejected, rejected. The idea's rejection is in its own partition.
  - **Conflicts, as the planner treats them:** concurrent pairs of deadline, priority, estimate and splittable edits.
    - Each second edit is `accepted_with_conflict`, and both candidates stay.
    - R1's record shows the earliest deadline, urgent priority, 120 minutes and not splittable. `changeSequence` is 4, one per material change.
  - **Deletion:** R1's record is removed. A concurrent rename arriving after it is accepted and stays superseded.
  - **Core's pages on replicas:**
    - The iPad's own saved operation is accepted at position 6.
    - One page `(0, 6]` installs on the iPad's replica with six entries. The replica's views equal Core's views, the iPad's entry is accepted at 6 and no longer an overlay, and nothing further is offered after 6.
    - A Mac replica fed pages of two entries reached cursor 6 in three pages, with the same views and search.
  - **Restart:** positions, epoch and receipts survive (a retry is a duplicate). A ledger of another dataset is refused (`datasetMismatch`).
- **Lint:** the new files are clean. R1's one `Package.swift` finding (AddLines) moved from line 172 to 182 with the inserted lines.
- **Result: PASS.**

### M3-2 Full snapshots from Core (plan §8.4.3, §8.6.3; R2-L12 with Core's snapshots)

- **Code:** `CoreSnapshots.swift` (`CoreLedger.snapshot`), a new `encodingFailed` error case, and `docs/SYNC-PROTOCOL.md` §8d.
- **Harness:** `m3/harness-v3/`, 4/4 on its first run (helpers copied from v2). One test builds an operation it never submits; it was left in by mistake and changes nothing.
- **Full build and R1 suite:** `m3/suite-after-core-snapshots-20261125T015339Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Cases:**
  - **A new replica:** Core held 12 tasks (created, renamed, some notes, one deleted) and a rejected edit. The snapshot at the newest position, in chunks of four, has 8 pages for 29 accepted entries; the rejection is left out.
    - It installs on a new replica, and the cursor is the cut.
    - Every task's view equals Core's. Search finds the 11 renamed tasks still alive, and the deleted one is deleted.
  - **Pages from the cut:** after the installation, Core's page from the cut applies (cursor cut + 1, one entry), and the views stay equal.
  - **A replica behind, with pending work:**
    - **Before:** the replica had applied a first page of two entries, then saved a capture offline.
    - **The installation:** a newer snapshot installs.
    - **After:** the pending capture stays in the view and in the journal, pending, and found by search. Core's tasks equal Core's views.
  - **A tampered chunk:** one byte changed is refused as not included under the signed root, and the installation doesn't complete.
- **Result: PASS.** Snapshots of windowed bucket partitions, and repairs from Core, come with the change feed for calendar occurrences.

### M3-3 Core receipts verified on a replica (R2-L15 with Core's receipts; plan §8.2.1)

- **Code:** in LisaReplicaStore, `recordReceipt(_:coreKey:)` and the `unverifiedReceipt` error case; `docs/SYNC-PROTOCOL.md` §8d, with the receipt's vector.
- **Harness:** `m3/harness-v4/`, 3/3 on its first run (helpers copied from v2).
  - **Regression package v5** (`m2/make-regressions-v5.py`, run `m2/regressions-run-20261125T015607Z/`): v4's targets plus M3 v3 and v4, 22 in all. All pass with their usual counts, and so do v35 and v47. The volume then had 1.1 GB free.
- **Full build and R1 suite:** `m3/suite-after-replica-receipts-20261125T015555Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Cases:**
  - **Verified receipts recorded:**
    - The iPad's capture, accepted by Core, is recorded from Core's final receipt: accepted at position 1 and synced with Core. It is still an overlay until canonical state installs, and its bytes are the receipt's body and signature. Recording it again changes nothing.
    - A note waiting for an operation Core lacks is recorded from Core's provisional receipt as waiting, with no position.
  - **Refused, changing nothing:**
    - a receipt signed by another key (`invalidSignature`);
    - Core's receipt for another dataset (`wrongDataset`);
    - Core's receipt for another digest (`receiptMismatch`).
    - The entry stays pending, with no receipt and not synced.
  - **Wire form:** the vector of §8d decodes back to the same value. A provisional receipt lists its missing IDs, and a final receipt without a position is refused.
- **Result: PASS.** With M2-19, a peer's acknowledgement never counts as commitment, and a receipt counts only when it verifies by Core's key.

### M3-4 The direct path end to end over loopback HTTP, first slice (R2-L04 direct and R2-L14 lookup over HTTP; plan §8.6.5, §8.12.1)

- **Code:**
  - `SyncWire` (LisaSyncProtocol).
  - The new modules LisaCoreAPI (`CoreAPIRouter`), LisaSyncEngine (`CoreTransport`, `CoreSession`) and LisaSyncHTTP (`HTTPCoreTransport`).
  - R1's `HostAPIServer.start` with a defaulted v2 hook, and `HostEndpoint.url(for:)` accepting `/v2/`.
  - `docs/DECISIONS.md` D-60; `docs/SYNC-PROTOCOL.md` §8e.
- **Full build and R1 suite:**
  - The first build failed: two decode closures in `HTTPCoreTransport` inferred untyped throws. That was fixed before any commit.
  - `m3/suite-after-v2-path-20261125T020303Z/`: debug build 0 warnings, 376 tests in 66 suites passed.
- **Harness:** `m3/harness-v5/`, 2/2 on its first run.
  - **Regression package v6** (v5's targets plus this one, 23 in all; `m2/make-regressions-v6.py`):
    - **First run** (`m2/regressions-run-20261125T020558Z/`): its build failed when the project volume filled (63 MB free), so every target failed. No test ran.
    - **Space:** superseded build output from M1 was removed from `.build/` (`m3/disk-reclaim-20261125T020802Z.txt`, 611 MB).
    - **Second run:** the same sources, built in a scratch path on the root volume by `m2/run-regressions-v7.sh` (`/tmp/lisa-r2-20261124-r2-5462/regressions-scratch`, 3.2 GB; logs and evidence in `m2/regressions-run-20261125T020817Z/`). All 23 targets pass with their usual counts, and so do v35 and v47.
  - R1's host was opened as `lisa serve` opens it, offline, with its devices listener on a free loopback port and Core's ledger on its store.
  - The v2 router was passed to the server, and an iPad was paired in process for a bearer credential.
- **Cases:**
  - **Reconciliation over HTTP:**
    - **Before:** Core held the phone's task (created, then renamed), and the iPad's replica had two captures saved.
    - **The session:** one reconciliation through LisaSyncHTTP over LisaClient's `URLSessionTransport` applied the baseline page and submitted both captures, recording Core's two receipts after verifying them. It then applied the page carrying them.
    - **After:** both captures are accepted at positions 3 and 4 and no longer overlays, the cursor is at 4, and every view equals Core's.
    - **v1 on the same server:** `GET /v1/tasks` with the same credential lists the captures and the rename. Work submitted through v2 is visible to R1's API through the projection.
    - **Again:** a second reconciliation submits, applies and records nothing.
  - **The routes:**
    - **Authentication:** a request without a valid credential gets 401 `unauthenticated`.
    - **Capabilities:** they name the dataset, the epoch and head 0.
    - **Idempotency:** a submission sent twice gets the same receipt, `receipted` then `duplicate`, and it verifies by Core's key.
    - **Lookup:** a receipt lookup answers the known operation's receipt and none for an unknown one.
    - **Unknown route:** an unknown v2 route is a 404.
- **Not yet in this slice:**
  - **Network:** TLS on the devices listener with the Linux pin evaluation through the test-only libcurl transport (§8.6.5).
  - **Body limit:** the plan's 512 KiB request limit for `POST /v2/operations` (D-60).
  - **Other routes:** enrollment, trust and the other v2 routes (M3-5 onward).
- **Result: PASS** for this slice.

### M3-D61 Opening the replica at 0 bytes free by releasing its ballast (the owner's decision of 2026-11-25; `docs/DECISIONS.md` D-61; S-17; plan §8.15.2 amended)

- **Override:** plan §8.15.2 releases the ballast only on the capture path. The owner allowed releasing it to open the replica at launch, with the override, the affected file and the recovery recorded in each report.
  - **The file:** the replica's `reserve.bin`, truncated to 0 bytes; the file itself stays.
  - **Recovery:** `restoreBallastIfSpaceReturned()`, or a later launch once space has returned.
- **Code:** `ReplicaStore`'s initializer counts an open as failed for lack of space on `SQLITE_FULL`, or on SQLite's I/O error while less than a reserve is free. Then it empties the ballast and opens once more, reporting `releasedBallastAtOpen` and `storageIsAlmostFull`. With nothing left to release, the error is `storageFull`.
- **Found by the container run:** a full tmpfs fails the reopen with SQLite's I/O error ("disk I/O error"), not `SQLITE_FULL`. The first version, keyed to `storageFull` alone, therefore didn't release anything. The space check fixed it, and the same harness then passed.
- **Harness:** `m3/harness-v7/` (v6 didn't compile: a `try` inside an expectation's right-hand operand, kept unchanged). It is built in `m3/harness-v7-scratch`.
  - On the host, 2 tests: a normal open releases nothing (the tmpfs case skips there).
  - In the pinned container, 1 test: `swift@sha256:9733821c…430097`, a 24 MiB tmpfs, no network, the rootful engine; script `m3/container-20261125T0604Z/run-d61-v1.sh`, run `run-20261125T060502Z`.
- **Cases (container):**
  - A replica with a 4 MiB ballast saved one capture and closed, and a filler then took the tmpfs to 0 bytes free.
  - **The reopen:** it released the ballast and succeeded, reporting both flags, with the ballast at 0 bytes, two incarnations, and the earlier capture present and found by search.
  - **A capture right after:** saved, with the journal one longer. Had it failed, the expectation was "not saved" with the journal unchanged.
  - **Filled to 0 again, with the ballast already empty:** opening failed as `storageFull`.
  - **The filler emptied:** the replica opened without releasing anything, the ballast was restored whole, every saved capture was present, and `integrity_check` was ok. A last open released nothing.
- **Full build and R1 suite:** `m3/suite-after-ballast-at-open-io-20261125T060530Z/`, debug build 0 warnings, 376 tests in 66 suites passed.
- **Regressions:** regression package v6 (`m2/run-regressions-v7.sh`, run `m2/regressions-run-20261125T060539Z/`) passes all 23 targets with their usual counts, and v35 and v47 pass in their own packages.
- **Result: PASS.**

### M3-5a Enrollment and the roster end to end over loopback HTTP (S-05's Core and device rules; R2-TRUST-01, -02 in part; plan §8.1.2, §8.1.3, §8.12.1)

- **Code:**
  - `TrustRoster` and `EnrollmentMessages` (LisaSyncProtocol); `RosterSigning`, `EnrollmentSigning`, `CoreCredential` and the domain `lisa-r2-device-authorization-v1\n` (LisaTrust).
  - Schema v6 (LisaStore), `CoreTrust` (LisaCoreLedger), and `CoreAPIRouter(trust:)` with `POST /v2/enrollments`, `GET /v2/trust/tls-anchors` and `GET /v2/trust`.
  - `ReplicaTrust` (LisaReplicaStore), `CoreEnrollment` (LisaSyncEngine) and `HTTPEnrollmentTransport` (LisaSyncHTTP).
  - Records: `docs/DECISIONS.md` D-62; `docs/SYNC-PROTOCOL.md` §8f.
- **Full build and R1 suite:**
  - `m3/suite-after-enrollment-20261125T065306Z/`: before lint formatting.
  - `m3/suite-after-enrollment-formatted-20261125T065446Z/`: the committed sources.
  - Each: debug build 0 warnings, 376 tests in 66 suites passed with schema v6. `swift format lint` is clean on every new and changed file.
- **Harness:** `m3/harness-v10/`, R1's host serving the v2 routes on its devices listener over loopback HTTP. It passed 8/8 on its first run (`harness-v10-test-20261125T065354Z.log`) and again on the committed sources.
  - **The rerun's evidence** carries an empty timestamp, from a shell slip: `harness-v10-test-.log`, `harness-v10-work-`. It is kept as written.
  - **Earlier versions,** kept unchanged: v8 was corrected before its first build, and v9 failed to compile (a missing import, five `#expect(a && (try b))`).
  - **The pending item:** a file-backed stand-in for the Keychain item, which writes new numbered files and deletion markers.
- **Cases:**
  - **`pin` mode:**
    - No anchors GET, and one POST under the owner text's pin and host.
    - The verified result completes in one replica transaction (dataset, device ID, trust state, roster), and the pending item goes.
    - Core lists the device as never seen. The capture saved before pairing is signed after enrollment and accepted with the new credential; the device is then seen.
    - `GET /v2/trust` serves the signed roster, and refuses an unknown credential (401). The anchors route is a 404.
    - No token byte, token text or credential byte appears in any replica or Core file.
  - **`ca` mode:**
    - The anchors GET under the bootstrap pin, then the POST under the verified CA and intermediates. The roster's `anchorsDigest` is the bundle's.
    - A tampered bundle, a bundle signed by another key, a wrong CA digest, an old-format text (`lisa-pair:3:`) and a damaged text stop with zero POSTs and no pending item. The enrollment stays open with no attempt.
  - **The attempt limit:**
    - Four wrong tokens (403 `enrollment_rejected`, each kept pending) and a bad signature are counted; the fifth failure invalidates.
    - The genuine text is then refused with 410 `enrollment_invalidated`, which removes the pending item. Each failure is a trust event.
    - An unknown enrollment gets 404.
  - **Concurrent requests:** one consumes, the other digest gets 409 `enrollment_consumed` with a security event and its item removed. One device.
  - **A lost answer:**
    - After the enrollment's expiry, a restarted client replays the identical bytes and gets the stored result. An exact replay returns the same bytes.
    - After 7 days Core answers 409 `enrollment_response_purged` naming the device, and the response is no longer kept.
    - A client past its retry deadline (expiry plus 24 hours) stops locally, with no POST.
  - **Tampered results after one valid POST:** an altered response, another enrollment's correctly signed result (`binding("enrollment")`) and a replaced roster (`binding("rosterDigest")`) each leave trust uninstalled with the item kept. The exact replay then completes: two devices, two consumptions, five POSTs.
  - **The device limit,** configured to 2: 409 `enrollment_device_limit`, counted, the enrollment still open.
  - **Signer rotation:**
    - A Core restarted under a new key invalidates an open enrollment issued under the old one (410, `signer_rotated`).
    - An already consumed exact replay still returns its original result, which the device verifies with the original issuer.
    - Core's current roster verifies only under the new key.
  - **Revocation:**
    - A new roster version records the revocation at the current epoch and position 1. Repeating it changes nothing.
    - The revoked device's credential gets 401, and its operation relayed by another device is `unverified`.
    - The peer accepts the newer roster, records the revocation, drops the key, and refuses the older roster.
    - The revoked device's committed task stays at Core.
- **Regressions:**
  - **Regression package v7** (`m2/make-regressions-v7.py`, v6's targets plus harness v10; run `m2/regressions-run-20261125T065639Z/`): 23 of 24 targets pass, and so do v35 and v47.
    - M2's harness v49 failed one expectation: it pins the replica schema's exact table list, which now has `trust_rosters` and `trust_state`.
    - This was the intended schema change, not a change in behaviour.
  - **Its successor,** `m3/harness-v12/`, is v49 with the two names added to the list, nothing else.
  - **Regression package v8** (`m2/make-regressions-v8.py`, v49 replaced by v12; runner `m2/run-regressions-v9.sh`; run `m2/regressions-run-20261125T070034Z/`): all 24 targets pass, and so do v35 and v47.
  - The generated regression manifests' comments still name an older scratch path; the runners use the root-volume path.
- **Result: PASS** for this slice.

### M3-5b S-04 and S-05 over R1's real TLS server with the test-only libcurl pinning transport (R2-TRUST-01, -02; plan §8.1.2 step 3, §8.1.4 TLS rotation, §8.6.5, §10.4)

- **Harness:** `m3/harness-v14/`, 5/5 on its first run (`harness-v14-test-20261125T070718Z.log`).
  - v11 was corrected before its first build, and v13 failed to compile (a `do` block mixing error types). Both are kept unchanged.
  - Certificates and P-256 keys are made at run time with the openssl CLI (OpenSSL 3.5.9) in each test's own directory, valid for 30 days. Pins are computed by openssl, independently of Lisa.
  - R1's host serves Core's v2 routes over native TLS (SwiftNIO) on its devices listener, with the chain and key passed as secrets.
- **The transport** (`PinTransport.CurlPinAPITransport`, harness-only), an `APITransport`, so LisaSyncHTTP's own enrollment and sync transports run over it.
  - **libcurl 8.14.1,** through a C shim whose header never includes `curl.h`, so its module can't clash with R1's CCurl.
  - **Every exchange** uses a fresh connection, with no redirects, no proxy and TLS 1.2 or later. The host is always checked, and libcurl's `PINNEDPUBLICKEY` holds the authorized pins.
  - **`pin` mode:** a handshake-only probe checks the host and pins. The leaf it saw becomes the only anchor of the exchange's own connection, which checks host, pins and validity again.
  - **`ca` mode:** the owner CA is the only anchor, with no partial chain and the default CA path disabled. The bundle's intermediates help build the chain.
  - A debug callback records every byte sent before encryption. `CURLOPT_CONNECT_TO` keeps the owner text's URL (`https://core.lisa.test:8443`) while connecting to the loopback port.
- **Cases:**
  - **`pin` mode** with a self-signed leaf and with a CA-issued leaf: enrollment with no anchors GET, then sync under the roster's pins. The capture holds the POST's exact request body, a positive control that it would show a token sent.
  - **`ca` mode** with the root omitted (leaf and intermediate served), a leaf signed directly by the root (leaf alone), and an intermediate the server omits, supplied from the signed bundle. Each runs the anchors GET under the bootstrap pin, the POST under the CA, then sync. Without the bundle's intermediate, the omitted-intermediate chain fails.
  - **Before the POST**, with zero enrollment POSTs at Core, no saved request, and no POST, token byte or token text in the device's captured bytes:
    - **A wrong pin:** the probe fails, with no GET either.
    - **A wrong CA digest:** one token-free GET, then `binding("caDigest")`.
    - **A bundle signed by another key than the owner text's:** one token-free GET, then `invalidSignature`.
    - **A leaf naming another host:** the probe fails on the host check, with no GET.
    - **A server chain the bundle's CA doesn't anchor:** the POST's own connection fails its handshake before sending a byte.
  - **TLS rotation (§8.1.4):**
    - A renewal that keeps the leaf key needs nothing.
    - Core announces the new key's pin as next (pins `[A, B]`), and the device that fetched that roster accepts the newly keyed leaf.
    - The device holding the older roster (`[A]`) is refused, then recovers by taking the peer's newer roster.
  - **A lost answer in both modes:** the pending item keeps the saved policy, and the replay repeats every TLS check with the identical request body. One device, one consumption, two POSTs.
- **Not yet covered here:** an expired certificate, Design B certificates, and the X2 device runs (owner).
- **Result: PASS** for this slice.

### M3-5c Credential reset and challenges (R2-TRUST-03 and R2-CORE-06 in part; plan §8.1.4 credential reset, §8.1.5; S-10's challenge cases)

- **Code:**
  - `CredentialReset` and `Challenge` (LisaSyncProtocol); `CredentialResetSigning`, `ChallengeSigning` and the domain `lisa-r2-credential-reset-v1\n` (LisaTrust).
  - `CoreTrustRequests` and `CoreTrust`'s monotonic clock and run generation (LisaCoreLedger).
  - The credential-free routes `POST /v2/devices/current/credential-reset` and `POST /v2/challenges` (LisaCoreAPI), and `HTTPTrustRequests` (LisaSyncHTTP).
  - Records: `docs/SYNC-PROTOCOL.md` §8g.
- **Found by the harness:**
  - `CoreTrust.revoke` spent the device's open challenges, so a response after a revocation came back as a reuse (`used`) instead of `revokedDevice`. The caller needs `revokedDevice` to quarantine the upload (§8.1.5).
  - Revocation now leaves challenges to their verdict, as the plan's revoke (§8.1.3) lists nothing about challenges.
  - The harness's first run (`harness-v15-test-20261125T071451Z.log`) shows the failure, and its second run passes on the fixed source.
- **Full build and R1 suite:** `m3/suite-after-reset-challenges-20261125T071556Z/`, debug build 0 warnings, 376 tests in 66 suites passed. `swift format lint` is clean.
- **Harness:**
  - **`m3/harness-v15/`** (v10's 8 tests unchanged, plus 2): 10/10 (`harness-v15-test-20261125T071536Z.log`).
  - **`m3/harness-v14/`** (TLS) passes 5/5 again on these sources (`harness-v14-test-20261125T071556Z.log`).
- **Regressions:** regression package v9 (`m2/make-regressions-v9.py`, harness v10 replaced by v15, which holds its tests unchanged; runner `m2/run-regressions-v10.sh`; run `m2/regressions-run-20261125T071659Z/`) passes all 24 targets, and v35 and v47 pass in their own packages.
- **Cases:**
  - **Credential reset over loopback HTTP:**
    - The owner's token with a new verifier signed by the device's existing key replaces the credential: the old one gets 401 and the new one 200.
    - A request signed by another key is refused with 403 `credential_reset_invalid`, and the token stays usable.
    - Refused afterwards: a reused token (410 `credential_reset_used`); a token past 10 minutes (410 `credential_reset_expired`); a wrong token (403); an unknown device (404).
    - After revocation, no token is issued, and an open token is refused (403 `device_revoked`). One `credential_reset` trust event.
  - **Challenges:**
    - Issued over HTTP with the plan's fields (120 seconds, a 32-byte nonce), answered with the operation key, and verified once; a second use is refused (`used`).
    - **Refused:** after 121 seconds on Core's monotonic clock (`expired`); a body changed after signing (`invalidSignature`); a response signed for another epoch (`invalidSignature`, the genuine response still verifying); another purpose (`purposeMismatch`); a Core restart between issue and response (`otherRun`); an unregistered device, or an enrolled device answering with a key the registry doesn't hold (`unknownKey`, the trust-bundle path); an unknown challenge ID (`unknown`).
    - **Unchanged:** a one-hour backward wall-clock step.
    - **A revocation between issue and response:** refused as `revokedDevice`, after which the challenge is spent.
    - **A malformed issue body:** 400.
- **Not yet covered here:**
  - **Consumers:** the routes that consume a proof come with M3-7 and the migration spans, and so does quarantine storage for a revoked device's upload.
  - **Epochs:** an epoch change between issue and response is checked by code (`otherEpoch`); M3-7 will exercise it, because no epoch changes before restore exists.
- **Result: PASS** for this slice.

### M3-5d, first items: an expired certificate and roster renewal (plan §8.1.4 "an expired certificate is never accepted", §8.1.3 renewal)

- **Harness:** `m3/harness-v16/` (v14's 5 TLS tests unchanged, plus 1), 6/6 on its first run (`harness-v16-test-20261125T071909Z.log`). The expired leaves were made with OpenSSL 3.5.9's `-not_before`/`-not_after`, valid only on 2025-01-01.
- **Cases:**
  - **First contact with an expired leaf:**
    - In `pin` mode, the pin-and-host probe passes, but the POST's own connection refuses the expired pinned leaf as its anchor, so no POST reaches Core.
    - In `ca` mode, the anchors GET's own connection refuses it, so no GET reaches Core either.
    - Either way, nothing of the request leaves the device.
  - **An enrolled `ca` device:** it refuses Core once Core serves an expired leaf with the same key and pin.
  - **Roster renewal,** with the interval configured to 60 seconds:
    - `renewRosterIfDue()` returns the current roster until the interval passes, then signs the next version with a later `issuedAt`.
    - The device fetches it over TLS, accepts it, and then refuses its older roster.
- **Code:** none changed; this exercises M3-5a's `renewRosterIfDue()` and the transport's evaluation.
- **Still open in M3-5d:**
  - signing-key rotation with dual-signed transitions, key history and historical receipts;
  - K2's private half imported on a fresh host, with a mismatching key refused;
  - export-key rotation, with an old archive still opening;
  - device key rotation;
  - re-anchoring, with M3-7's restore and S-10.
- **Result: PASS** for these items.

### M3-4b Capabilities negotiation (plan §8.12.1; `docs/DECISIONS.md` D-63)

- **Code:** `SyncWire.Capabilities.features` and `SyncWire.majorVersion(of:)`; `CoreAPIRouter`'s negotiation; `CoreSession`'s `incompatibleCore`. Records: `docs/SYNC-PROTOCOL.md` §8e.
- **Full build and R1 suite:** `m3/suite-after-negotiation-20261125T072315Z/`, debug build 0 warnings, 376 tests in 66 suites passed. Lint is clean.
- **Harness:** `m3/harness-v17/` (v15's 10 tests unchanged, plus 1), 11/11 on its first run (`harness-v17-test-20261125T072245Z.log`). `m3/harness-v16/` (TLS, 6/6) passes on these sources too (`harness-v16-test-20261125T072315Z.log`).
- **Cases:**
  - **Capabilities** list Core's features.
  - **Refused with 426 `upgrade_required`:** `Lisa-API-Version: 3.0`; a required `teleportation`; an enrollment POST sent as 3.1, refused before routing, so no attempt is counted.
  - **Answered:** 2.7; the required features `trust,enrollment`; and a request without a version header.
  - **The client's session** refuses a Core that answers 3.0 (`incompatibleCore("3.0")`).
- **Regressions:** regression package v10 (`m2/make-regressions-v10.py`, harness v15 replaced by v17; run `m2/regressions-run-20261125T072348Z/`) passes all 24 targets, and v35 and v47 pass too.
  - The targets ran from its build at 07:24:03Z, of the committed negotiation sources.
  - v35 and v47 build in their own packages, and did so after 07:25Z, so they include the then-uncommitted per-path limit (M3-4c), which regression package v11 covers.
- **Result: PASS.**

### M3-4c The per-path body limit for `POST /v2/operations` (plan §8.12.1; `docs/DECISIONS.md` D-60, D-64)

- **Code:**
  - R1's LisaAPIServer gains `APIServerLimits.bodyLimitsByPath`, empty by default, and the request assembler takes the request path's own limit when one is configured. Exceeding either limit is the same 413 and close.
  - `CoreAPIRouter.bodyLimits` names `/v2/operations` at 512 KiB, for the composition root to pass.
  - No R1 test changed.
- **Full build and R1 suite:** `m3/suite-after-body-limits-20261125T072632Z/`, debug build 0 warnings, 376 tests in 66 suites passed, including R1's 413 tests. Lint is clean.
- **Harness:** `m3/harness-v18/`: v17's 11 tests unchanged, with its server started under `CoreAPIRouter.bodyLimits`, plus 1. It passed 12/12 on its first run (`harness-v18-test-20261125T072608Z.log`).
- **Cases:**
  - A 300 KiB body to `POST /v2/operations` reaches the router: a 400 `invalid_request`, since it isn't a valid submission. 600 KiB gets 413.
  - The same 300 KiB to `POST /v1/captures` and to `POST /v2/receipts/lookup` gets 413, R1's 256 KiB limit.
  - Ordinary requests are answered as before.
- **Regressions:** regression package v11 (`m2/make-regressions-v11.py`, harness v17 replaced by v18; runner `m2/run-regressions-v12.sh`; run `m2/regressions-run-20261125T072713Z/`) passes all 24 targets, and v35 and v47 pass too.
- **Release:** a release build of the whole package (`m3/release-build-20261125T072841Z/`, scratch `.build/r2-release`) completes with 0 warnings. It started from the manifest before `1daf65f`'s formatting-only wrap.
- **Lint:** the whole-tree lint (`m3/lint-tree-20261125T072843Z.log`) found three over-long R2 target lines in `Package.swift`, from `9cc02f4`. They were wrapped in `1daf65f`, and R1's own finding is the only one left.
- **Result: PASS.** M3-4 has nothing left open beyond the M3 boundary's full runs.

### M3-5d, export-key rotation (plan §8.1.4 "an export-key rotation with an old archive still opening")

- **Code:** `CoreExportKeys` (LisaCoreLedger): the current export key, whose public half the roster announces, and every retired key, picked by the key ID an archive names (SHA-256 of the SubjectPublicKeyInfo DER, the archive format's own). `CoreTrust` already signs a new roster version when its export key changes.
- **Harness:** `m3/harness-v19/` (v18's 12 tests unchanged, plus 1), 13/13 on its first run (`harness-v19-test-20261125T073122Z.log`).
- **Full build and R1 suite:** `m3/suite-at-head-20261125T073144Z/` at `6e55294`, debug build 0 warnings, 376/66 passed.
- **Cases:**
  - An archive sealed by the device to Core's export key K1 (a `core-roster` recipient, signed by the device).
  - **The rotation:** Core takes K2, and its next roster announces K2. The device fetches it over HTTP and accepts it.
  - **Opening:** the old archive opens with the retained K1, and an archive sealed to the announced K2 opens with K2. An archive sealed to a key Core never held finds none. The old archive is still authentic by the device's key.
- **Result: PASS.** Still open in M3-5d: signing-key rotation with key history, K2's private half imported on a fresh host, device key rotation, and re-anchoring (with M3-7).

### M3-5d, signing-key rotation and K2 on a fresh host (plan §8.1.4 "signing-key rotation with historical receipts, K2's private half imported on a fresh host (and a mismatching key refused)"; `docs/DECISIONS.md` D-65)

- **Code:**
  - `SigningKeyTransition` and `EnrollmentWire.trustBody`/`trust(fromBody:)` (LisaSyncProtocol); `CoreKeyHistory`, `KeyTransitionSigning` and the domain `lisa-r2-key-transition-v1\n` (LisaTrust).
  - Schema v7 (`core_signing_keys`); `CoreLedger`'s open check and retirable signer; `CoreSigningKeys` (rotation, history, `importKeyTransition`).
  - `GET /v2/trust` with `keyTransitions`; the replica's `trust_key_transitions`, `keyHistory`, `acceptKeyTransitions` and `recordReceipt(_:keys:)`; `CoreSession(replica:transport:)`; `HTTPCoreTransport.trust()`.
  - Records: `docs/SYNC-PROTOCOL.md` §8h.
- **Full build and R1 suite:** `m3/suite-after-key-rotation-20261125T113411Z/`, debug build 0 warnings, 376/66 passed with schema v7.
- **Harness:** `m3/harness-v20/` passed 15/15 on its first run (`harness-v20-test-20261125T113341Z.log`). It holds v19's tests, except that the signer case now rotates through a transition before Core reopens with the next key, as D-65 refuses a reopen with a key the history doesn't hold. `m3/harness-v16/` (TLS) passes 6/6 on these sources.
- **Cases:**
  - **The transition:** sequence 1, activating at position 2, from K1 to K2, signed by both keys.
  - **The rotating ledger** refuses to sign again (`signerRetired`). Reopening the store with K1 is refused (`signerRetired`), and so is a key the history doesn't hold (`signerMismatch`).
  - **Core reopens with K2:**
    - The device's session takes the transition and the K2-signed roster first.
    - Its new capture is accepted at position 2, under K2. Its history reads K1 for position 1 and K2 from position 2.
    - The historical receipt at position 1 verifies by the history and not by K2 alone.
  - **Refused:** a receipt for position 3 signed by K1, and a newer roster re-signed by K1.
  - **A device enrolled after the rotation:** anchored at K2, it learns that its anchor's sequence is 1 and skips K1→K2.
  - **A second rotation, K2→K3:** it chains on both devices (sequences `[0, 1, 2]` and `[1, 2]`). A third rotation with nothing committed since the last is refused.
  - **Fresh hosts:**
    - **A store copied after the rotation** opens with K2, holds the transition, and refuses K1 and an unknown key.
    - **A store copied before it** refuses K2 until `importKeyTransition` adds the transition. A tampered transition is refused, importing twice changes nothing, and K1 is then refused.
    - **A forking transition** (K1→K4, from the retired K1) is refused.
- **Regressions:**
  - **Regression package v12** (`m2/make-regressions-v12.py`, v18 and v12 replaced by v20 and v21; run `m2/regressions-run-20261125T113520Z/`) is **invalid**.
    - Its build failed, because LisaArchive, which harness v19 and later import, wasn't among its products.
    - Its runner then ran every target with `--skip-build` against the previous round's binaries, so its "passes" test the older sources. It is kept as written.
  - **Package v13** added the product, and its runner (`run-regressions-v14.sh`) runs no target when the build fails. It was never run.
  - **Package v14** (`m2/make-regressions-v14.py`, v20 replaced by v22; runner `m2/run-regressions-v15.sh`; run `m2/regressions-run-20261125T114435Z/`) built with exit 0 and passes all 24 targets, and v35 and v47 pass too. This includes `m3/harness-v21/`, M3 harness v12 with `trust_key_transitions` added to the table list.
- **Result: PASS.** Later: appending the transition to the recovery ledger and backups, anchoring from a key backup, and backups older than the activation (M3-7); re-anchoring (S-10).

### M3-5d, device key rotation, and a revoked device's committed history (plan §8.1.4 "device key rotation", §8.1.3 "committed data stays"; `docs/DECISIONS.md` D-66)

- **Code:**
  - `DeviceKeyUpdate` and roster entries' `previousKeys` (LisaSyncProtocol); `DeviceKeyUpdateSigning`, `OperationSigning`'s `previousKeys` and the domain `lisa-r2-device-key-update-v1\n` (LisaTrust).
  - Schema v8 (`core_device_keys`); `CoreDeviceKeys`; `POST /v2/devices/current/key-update`.
  - The replica's verifiers with `previousKeys`, `rosterHistoricalKeys` and `resignLocalOperations`; `CoreSession`'s historical keys for pages; `HTTPTrustRequests.updateKey`.
  - Records: `docs/SYNC-PROTOCOL.md` §8i.
- **Full build and R1 suite:** `m3/suite-after-device-keys-20261125T114317Z/`, debug build 0 warnings, 376/66 passed with schema v8. Lint is clean.
- **Harness:** `m3/harness-v22/` (v20's 15 tests unchanged, plus 1) passed 16/16 on its first run (`harness-v22-test-20261125T114240Z.log`) and again on the committed sources (`…114337Z`), with v16 6/6.
- **Cases:**
  - **Refused before the update:** an update from a key the registry doesn't hold (403 `key_update_invalid`), one to the iPad's key (409 `key_update_key_in_use`), and one sent with the iPad's credential (403).
  - **The update:**
    - The new roster names the next key and lists the old one in `previousKeys`.
    - The device's pending capture is re-signed with the same body and digest and a new signature, then accepted at position 2.
    - An operation signed by the old key afterwards is `unverified`.
  - **The iPad** installs the page carrying the capture committed under the old key, by its previous key.
  - **A negative control:** a device verifying with current keys only refuses that page.
  - **Waiting work:** an operation of the device waiting for a dependency at Core blocks the next update (409 `key_update_operations_waiting`). One `device_key_rotated` trust event.
  - **After the device is revoked,** a device enrolled later installs both of its committed operations, by its previous key and its last key.
- **Regressions:** regression package v14 (above) passes on these sources.
- **Result: PASS.**

### M3-6a, first two steps: legacy children and Core's parents (plan §8.12.2; `docs/DECISIONS.md` D-67)

- **Code:**
  - `OperationOrigin.coreLegacyTranslation(incarnationID:sequence:)` (LisaSyncProtocol) and `LegacyChildIdentity.incarnationID` (LisaTrust).
  - The new module LisaLegacyRequests (`LegacyChildSet`, `LegacyChange`, `LegacyDerivation`).
  - Schema v9, and `CoreLegacyParents` (LisaCoreLedger: `legacyLookup`, `legacyConvert`, `LegacyTransaction.intake`, `legacyChildren`).
  - Records: `docs/SYNC-PROTOCOL.md` §8j.
- **Full build and R1 suite:** `m3/suite-after-legacy-children-20261125T115207Z/` and `m3/suite-after-legacy-parents-20261125T115548Z/`, debug builds 0 warnings, 376/66 passed with schema v9. Lint is clean.
- **Harnesses:**
  - **`m3/harness-v24/`,** 4/4 on its first run. v23 didn't compile: the payload type is `TaskFieldValue`, which has no notes case. v23 is kept.
  - **`m3/harness-v26/`,** v24's 4 tests plus 3, 7/7. v25 didn't compile: an `#expect(a && (try b))`. v25 is kept.
- **Cases:**
  - **The derivations** match an independent Python computation (the vectors in §8j).
  - **The same request** gives byte-identical envelopes twice. Every field is fixed (origin and sequences 1…3, versions, no creation time, `legacyParent`, one same-chain dependency). Two Core keys give the same digests and different signatures, each verifying only under its own key.
  - **Refused:** an empty request and a repeated discriminator.
  - **Chains:** 50 changes of one key form a chain of single dependencies; children of other chains don't depend on each other.
  - **Core takes a created task's child once:** the same child signed again is a duplicate with the same receipt, and a child signed by another key is `unverified`.
  - **The frame:**
    - One transaction takes the child, projects it so R1's record is readable in the same transaction, and records the parent with its answer.
    - A retry with the same key and fingerprint replays without converting again; another fingerprint is a mismatch; another scope is unknown.
    - A conversion that throws after its intake keeps nothing, and neither does one answering 503. A later conversion of the same request is kept.
    - A body past its retention reports `bodyExpired` with R1's status.
- **Result: PASS** for these steps. Next: R1's router hook and the two task routes under R1's semantics (M3-6a's third step).

### M3-6a, step 3 begun: one R1 revision step per R1 call (plan §8.12.2 "Projection revisions"; `docs/DECISIONS.md` D-68)

- **Code:**
  - `LegacyTransaction.intake(_:projecting:)` and `project(_:forceRevision:)`.
  - `TaskProjection.project(force:)`, which now returns the revision written, plus `recordRevision`.
  - Schema v10 (`core_projection_revisions`), and `CoreLedger.projectionPosition(of:revision:)`.
- **Full build and R1 suite:** `m3/suite-after-deferred-projection-20261125T120215Z/` and `m3/suite-after-projection-revisions-20261125T120421Z/`, debug builds 0 warnings, 376/66 passed with schema v10. Lint is clean.
- **Harnesses:**
  - **`m3/harness-v28/`** (v27 didn't compile: `TaskDraft` and `TaskCorrection` are LisaOwnerData's; kept):
    - **Passing:** against R1's own `TaskService` on an identical task, a correction of title and priority is one revision step, and so is a correction that changes no value; R2's projection of the same requests' field children, deferred and projected once, gives the same steps; without the forced step, a no-change correction takes none.
    - **Failing, as recorded:** two value expectations. The diagnostic copy, `m3/harness-v29/`, shows why: both legacy edits are `accepted_with_conflict`, so the merged title is `["Book the hall", "Book the big hall"]`, and the display-order first wins.
    - **The cause:** "observed at projection revision N" (D-68), which comes next.
  - **`m3/harness-v30/`** (v26's 7 tests plus 1), 8/8: the creation is revision 1 at position 1, and a two-field correction projected once is revision 2 at the position of its last child.
- **Result: PASS** for the revision steps and the map. Legacy edits' supersession is open (next).

### M3-6a, the observed set's projection revision (plan §8.3.2 "observed at projection revision N", §8.12.2)

- **Code:**
  - `ObservedSet.projectionRevision`: R1's `expectedRevision` from the request. It stands alone, without horizon, pieces, digest or group; it is at least 1 and encoded only when present, so every other observed set's bytes are unchanged.
  - `OperationEnvelope` refuses it on a device's operation (`legacyMismatch`).
  - The patch was applied by `m3/patch-projection-revision-v2.py`. v1, which lacked the decoder and the envelope rule, was never run and is kept.
- **Full build and R1 suite:** `m3/suite-after-observed-revision-20261125T120825Z/`, debug build 0 warnings, 376/66 passed. Lint is clean.
- **Harness:** `m3/harness-v31/` (v30's 8 tests plus 1), 9/9 on its first run (`harness-v31-test-20261125T120804Z.log`).
- **Cases:**
  - The encoding is `{"pieces":[],"projectionRevision":4}` and round-trips. An observed set without it still encodes as `{"pieces":[]}`.
  - **Refused:** revision 0, and a projection revision beside pieces.
  - A Core-signed legacy child carries it through signing and decoding; a device's operation with it is refused.
- **Regressions:** regression package v16 (`m2/make-regressions-v16.py`, v26 replaced by v30; run `m2/regressions-run-20261125T120453Z/`) passed all 25 targets, and v35 and v47 passed too, before this change. Package v17 (v30 replaced by v31; run `m2/regressions-run-20261125T120847Z/`) then passed all 25 targets on it, and v35 and v47 passed too.
- **Result: PASS.** Next, Core mapping N to the horizon of the state it reflected, at decision time, and serving it to replicas (§11).

### M3-6a, observed horizons at Core: "observed at projection revision N" resolved when Core decides the child (plan §8.3.2, §8.12.2; `docs/DECISIONS.md` D-69)

- **Code:**
  - Schema v11 rebuilds `core_projection_revisions` with each revision's epoch, and adds `core_operations.observed_epoch` and `observed_position` (`1a8436e`).
  - `TaskProjection.recordRevision` writes the epoch (`2399cda`), and `CoreOperationRecords.resolveObservedRevision` resolves N to `(epoch, "tasks", P(N))` at decision (`0e313a2`). `CoreLedger.apply` calls it before the fold (`ce45e30`), and `CoreTaskFold.view` folds with the stored horizon (`e5bea9a`).
  - `LegacyChange.observedRevision` puts N in the child (`6b3ec91`).
  - `1a8436e` builds alone but its projections fail until `2399cda`.
- **Full build and R1 suite:** `m3/suite-after-observed-horizon-20261125T121653Z/`, debug build with tests 0 warnings, 376/66 passed with schema v11. Lint is clean on the six files.
- **The migration's copy path:** `m3/check-migration-v11-v1.py` (log `m3/check-migration-v11-v1-*.log`, SQLite 3.46.1) reads v11's statements from `Migrations.swift` and applies them to a v10-shaped database with two revisions and an operation. Both revisions are copied with the dataset's epoch. Five writes are refused: one observed column without the other, a negative position, a short epoch, and a revision without its epoch. **PASS.**
- **Harness:** `m3/harness-v33/` (v31's 9 tests plus 6), 15/15 on its first run (`m3/harness-v33-test-20261125T121918Z.log`). v32 holds the same tests with two `#expect(Set(try …) == …)` forms, which v25 showed don't compile; it was superseded before its first build and is kept.
- **Cases:**
  - **The body:** the child carries N alone, `{"pieces":[],"projectionRevision":1}`, and the same request gives the same bytes.
  - **Supersession:** an edit observed at revision 1 supersedes the creation's title: `accepted`, one candidate, revision 2 at position 2. Two fields in one request each supersede their own field.
  - **Exactly P(N):** a second edit at revision 2 supersedes the first. After it, an edit observed at revision 1 covers only what revision 1 reflected: `accepted_with_conflict`, and the newer title stays beside it.
  - **No mapping:** an unmapped revision (9), or none, observes nothing: `accepted_with_conflict`.
- **Not yet:** replicas fold a legacy edit as observing nothing until Core serves the resolved horizon (D-69, "Open, next").
- **Regressions:** regression package v18 (`m2/make-regressions-v18.py`, v31 replaced by v33; runner `m2/run-regressions-v19.sh`, run `m2/regressions-run-20261125T122040Z/`) passes all 25 targets, and v35 and v47 pass too. 23.3 GB were free at its end.
- **Result: PASS** for Core's resolution. Next, serving the resolved horizon to replicas (`R2-CHECKPOINT.md` §11).

### M3-6a, observed horizons on replicas: Core serves the resolved horizon, replicas fold with it (plan §8.3.2, §8.12.2; `docs/DECISIONS.md` D-69)

- **Code:**
  - **The protocol:** `ChangeEntry.observedHorizon` (`53e2a5a`), `{"epochID", "partition", "position"}`, is encoded only when present, so every other entry keeps its bytes. It is refused on a derived record, on a rejection, and on any operation whose body isn't a legacy child carrying a projection revision.
  - **Core:** `CoreTaskFold.resolvedHorizon` is the one reading of `observed_epoch` and `observed_position` (`a2ae075`). Both entry builders serve it: change pages (`6867e7c`) and snapshot chunks (`ccce9e1`).
  - **The replica:**
    - `canonical_operations` and the staged installation table keep `observed_epoch`, `observed_partition` and `observed_position`, all or none (`6e84d1b`, `a59ce54`).
    - Pages and chunks store them (`6f091c9`, `a59ce54`).
    - The task fold uses the stored horizon in place of the observed set, as `CoreTaskFold.view` does (`89fcb1a`).
  - **Docs:** `docs/SYNC-PROTOCOL.md` §8, §8a and §8j now describe the projection revision and the served horizon.
- **Full build and R1 suite:** `m3/suite-after-replica-horizon-20261126T013338Z/`: the debug build with tests has 0 warnings and 0 errors, and 376/66 pass. Lint is clean on the eight files.
- **Harness:** `m3/harness-v34/`, v33's 15 tests copied unchanged plus 5. All 20 pass in 6 suites on its first build (`m3/harness-v34-test-20261126T013653Z.log`).
- **Cases:**
  - **The entry:** Core's page entry for an edit observed at revision 1 carries the horizon of the page's epoch, `tasks`, and the creation's position, which is P(1). The creation's entry carries none.
  - **Pages:** a replica pulling Core's pages three entries at a time has every view equal to Core's, in three cases:
    - supersession: one title;
    - a stale revision: the newer title beside it;
    - an unmapped revision: a conflict.
  - **A snapshot:** the same views after a full snapshot in chunks of two. The staged table keeps the horizon through the swap.
  - **Pages after a snapshot:** a later legacy edit arrives by page and folds with its horizon.
  - **The rules:**
    - A horizon on the creation's entry (no projection revision) is refused with `invalidField("entry.observedHorizon")`, and so is a horizon on a rejection.
    - `accepted_with_conflict` accepts one.
    - The entry round-trips through its canonical form. Its JSON holds `"observedHorizon":{"epochID":…`.
    - An entry without one has no such key and round-trips as before.
- **Regressions:** regression package v19 (`m2/make-regressions-v19.py`, with harness v33 replaced by v34; runner `m2/run-regressions-v20.sh`) passes all 25 targets, and v35 and v47 pass too (`m2/regressions-run-20261126T013734Z/summary.txt`). 22.6 GB were free. The background command around the runner reported exit 1 only because its final `cat` matched a stray `.txt` path; the runner itself exited 0.
- **Result: PASS.** A replica's view of a legacy edit equals Core's. Next, R1's router hook for `POST /v1/tasks` and `PATCH /v1/tasks/{id}` (`R2-CHECKPOINT.md` §11).

### M3-6a, R1's `POST /v1/tasks` through the legacy converter in R1's router (plan §8.12.2; `docs/DECISIONS.md` D-71)

- **Code:** `f4879b6` → `12bd3fb`:
  - `LegacyTransaction.now`;
  - R1's `TaskService` rules made public, unchanged;
  - the module wiring;
  - `LisaLegacyRequests.LegacyTaskRoutes`: R1's checks, `create:task` plus `field:notes` (D-71), one projection, R1's audit;
  - `RouterConfiguration.legacyConverter` (nil by default) and `APIRouter.converting(with:)`;
  - the shared `taskDraft(_:)`;
  - `LegacyRouting.swift`: R1's ledger and the parent consulted, the conversion recorded with R1's answer, replays, 422, the terminal reply, propagation after the commit;
  - the hook in `idempotent`.

  `LisaHost` doesn't enable it yet.
- **Full build and R1 suite on the committed tree:** `m3/suite-after-converted-create-committed-20261126T015435Z/`: 0 warnings, 0 errors, 376/66. With no converter, R1's path is unchanged. Lint is clean on the changed files, apart from R1's own `Package.swift` line, which HEAD already had.
- **Harness:** `m3/harness-v36/`, 7/7 on its first run (`m3/harness-v36-test-20261126T015349Z.log`). v35 failed to compile because `RequestOrigin.authenticateHeaders` takes `isLoopback:`; it is kept unchanged. Each case sends the same requests to R1's router on one host and to the converting router on another, at the same wall clock:
  - **The answer:** 201 with the same headers and the same `TaskDTO` but for its ID, which is the parent's derived task ID. The title is trimmed, the notes kept, revision 1. One `task.created` audit event with the same detail, actor and time.
  - **Replay:** the same request again replays with `Lisa-Replayed: true` and creates nothing more.
  - **Reuse:** the same key with another body gets R1's 422 on both.
  - **Refusals:** an empty title, minutes 0, a malformed body and an unknown zone give the same 400 bodies on both. Both record them and replay them. No child and no change-log entry exists for any of them.
  - **The children:** `create:task` and `field:notes`, both `applied`. A replica pulling Core's page shows the title, the notes and `high`.
  - **One key space:** a key the converted POST used gets 422 on the unconverted PATCH, and a key the PATCH used gets 422 on the converted POST, on both hosts.
  - **A paired device** creates under `device:<id>`, and the task ID is derived from that scope.
- **Regressions:** regression package v20 (`m2/make-regressions-v20.py`: v19 plus harness v36, with LisaAPI among the products; runner `m2/run-regressions-v21.sh`) passes all 26 targets, and v35 and v47 pass too (`m2/regressions-run-20261126T015451Z/summary.txt`). 22.2 GB were free.
- **Result: PASS** for `POST /v1/tasks`. Next, `PATCH /v1/tasks/{id}` (`R2-CHECKPOINT.md` §11).

### M3-6a, R1's `PATCH /v1/tasks/{id}` through the legacy converter (plan §8.12.2; `docs/DECISIONS.md` D-72)

- **Code:** `ae0c52d` → `6cc8073`:
  - **Two protocol rules:** `task.reopen` may name no action, and `note.replaceObserved` may be empty.
  - **The merge:** terminal actions keep commit positions; a reopen naming nothing reopens what its coverage covers; an empty replacement adds nothing.
  - **The projection:** the deadline owner-corrected hint, and `LegacyTransaction.recordProjectionRevision` for revisions the conversion writes itself.
  - **`LegacyTaskRoutes.update`:**
    - field children observed at N, projected once with `forceRevision`;
    - the status child (`task.complete`, `task.cancel`, or `task.reopen` naming nothing);
    - R1's own transition for in progress, blocked and an active task's return to open;
    - R1's refusals;
    - R1's audit events.
  - **The router:** the shared `taskCorrection(_:)`, and `convertUpdateTask` with PATCH's terminal replies.
- **Full build and R1 suite:** `m3/suite-after-converted-patch-final-20261126T020726Z/`: 0 warnings, 0 errors, 376/66. Lint is clean on the nine files.
- **Harness:** `m3/harness-v38/`, v36's 7 tests copied unchanged plus 8 PATCH tests, all against R1's path on a second host.
  - **15/15** on the run after the fix (`m3/harness-v38-test-20261126T020708Z.log`).
  - **Superseded before its first build:** v37. Three of its request IDs were under R1's 8-character minimum, and its audit order relied on timestamps that the fixed clock makes equal. It is kept, never built.
  - **v38's first run** (`m3/harness-v38-test-20261126T020602Z.log`) found a fault in the converter. A PATCH that only sets in progress or blocked has no child, and `update` returned before R1's transition. The fix makes the transition run with or without children.
  - **Found in review before that run:** the converter's R1-only writes didn't record their revision in the projection-revision map. The new test "an edit after an R1-only status" covers it.
- **Cases:** each answer has R1's status, headers and body, but for the task's ID:
  - **A correction of every field:** revision 2, and the `task.corrected` audit event.
  - **Clearing, and same values:** clearing the notes (an empty replacement) and the deadline; a same-value title and deadline, which still take a revision and mark the deadline owner-corrected, as R1 does.
  - **Refusals before any change:** a stale revision (409 with `currentRevision`), invalid minutes before the title (400), an empty title (400) and an unknown task (404). Each is recorded and replayed with `Lisa-Replayed: true`, the record isn't changed, and the converter takes in no child.
  - **Every status R1 allows, in turn:** completed, open, in progress, blocked, open, cancelled. Revisions 2–7 and the audit actions match R1's.
  - **A refused status after a correction:** cancelling a completed task (409, the status child `refused`, the title child applied) and setting a completed task in progress (409, no status child). The corrections are kept, as R1 keeps them.
  - **The same status:** no revision and no audit event.
  - **An edit after in progress:** it supersedes, so Core holds one title.
  - **A replica pulling Core's pages two entries at a time:** its view equals Core's after a correction, a completion and a reopen that names nothing but covers the completion through its served horizon.
- **Regressions:**
  - **Package v21** (`m2/make-regressions-v21.py`, with harness v36 replaced by v38; run `m2/regressions-run-20261126T020805Z/`): every target passed except M2 harness v15's `payloadsAreDecodedStrictly`. That test still expected an empty `task.reopen` list to be refused, which D-72 changed on purpose.
  - **M3 harness v39:** v15's tests with that expectation replaced, and an empty `note.replaceObserved` accepted. `note.add` with empty text is still refused. 7/7 (`m3/harness-v39-test-20261126T021157Z.log`).
  - **Package v22** (`m2/make-regressions-v22.py`, with v15 replaced by v39; runner `m2/run-regressions-v23.sh`): all 26 targets pass, and v35 and v47 pass too (`m2/regressions-run-20261126T021223Z/summary.txt`). 21.6 GB were free.
- **Result: PASS** for `PATCH /v1/tasks/{id}`, and with it M3-6a's v1 task routes. Next, M3-6b (`R2-CHECKPOINT.md` §11).

### M3-6b, first step: the preference operations, the key's entity and its register merge (plan §8.2.3, §8.3.1; `docs/DECISIONS.md` D-73)

- **Code:**
  - `95d3e55`: `PreferenceOperationPayload` and `PreferenceWireValue` in LisaSyncProtocol;
  - `15d6f1d`: `PreferenceEntity` in LisaTrust;
  - `fc1c17f`: `PreferenceMergeState` and `PreferenceView` in LisaMerge.
- **Full build and R1 suite:** `m3/suite-after-preference-model-20261126T022139Z/`: 0 warnings, 0 errors, 376/66. Lint is clean on the three files.
- **Harness:** `m3/harness-v41/`, 7/7 on its first build (`m3/harness-v41-test-20261126T022120Z.log`). v40 was corrected before its first build and is kept, never built:
  - an overloaded `.number` inside `#require`;
  - an optional matched with `if case`;
  - a text larger than the decoder's own limit, which would have tested the decoder instead of the value budget.
- **Cases:**
  - **Canonical forms and round trips:** a text, the numbers 0.8 (`"0.8"`) and 15 (`"15.0"`), a flag, a list, a delete and a confirm. An infinite or NaN number has no wire form.
  - **Strict decoding:** an empty key, a control character, and 257 bytes are refused, while 256 bytes and spaces are accepted. Refused too: `"1.50"`, `"nan"` and `"inf"`; an unknown kind; a non-string list item; 257 list items; an extra field; a missing value; an unknown type; and a 60,000-character text over the value budget.
  - **Entity IDs:** three keys, against Python's hashlib.
  - **The merge:**
    - a set replaces what it observed;
    - a delete clears what it observed;
    - a set after the delete re-creates the key;
    - a set the delete didn't observe survives as a conflict, still shown;
    - a model value beside an owner value is a suggestion;
    - a model value alone is unconfirmed until a confirmation observes it.
  - **Convergence:** all 720 orders of six operations (sets, a delete, a model set, a confirmation, committed and pending) give one state and one view.
- **Regressions:** regression package v23 (`m2/make-regressions-v23.py`, v22 plus harness v41; runner `m2/run-regressions-v24.sh`) passes all 27 targets, and v35 and v47 pass too (`m2/regressions-run-20261126T022204Z/summary.txt`). 21.3 GB were free.
- **Result: PASS** for the model. Next, Core's fold and projection for preferences (`R2-CHECKPOINT.md` §11).

### M3-6b, second step: preferences at Core and on a replica (plan §8.3.1, §8.4.1–§8.4.2; `docs/DECISIONS.md` D-73)

- **Code** (`f404e2c` → `44cb3ed`):
  - **The view** names its shown value's authority.
  - **The served horizon** takes the entry's partition, for page and snapshot entries.
  - **`CorePreferenceFold`:** Core's per-key fold, with resolved horizons.
  - **`PreferenceProjection`:** the projection into R1's `Preference` record.
    - The value maps through `PreferenceValue`.
    - The origin is `explicit` for an owner's value and `inferred` for a model's.
    - `confirmed` follows the view.
    - A key without a value has its record removed.
    - A `force` mode is there for R1's always-writing calls.
  - **`CoreLedger`:** preference operations are supported. Their schema and key-derived entity are checked, and they are merged, projected and logged in partition `preferences`. Read through `preferenceView(key:)`.
  - **The replica:** the same checks on saves and arrivals (`checkPayload` now takes the entity ID), and `ReplicaStore.preferenceView(key:)` folded as Core folds.
- **Full build and R1 suite:** `m3/suite-after-preference-ledger-20261126T022947Z/`: 0 warnings, 0 errors, 376/66. Lint is clean on the eight files.
- **Harness:** `m3/harness-v43/`, 5/5 on its first build (`m3/harness-v43-test-20261126T022921Z.log`). v42 expected no `tasks` page where Core serves an empty one; it is kept, never built.
- **Cases:**
  - **A device's set** is accepted and projected into R1's record: the value, `explicit`, confirmed, revision 1. A set that observed it updates the same record to revision 2.
  - **A delete that observed the set** removes R1's record and leaves the key absent. A set that observed the delete re-creates it with a new record ID, as R1's delete then set does.
  - **Two sets that didn't observe each other:** the second is `accepted_with_conflict`, and R1's record shows the first value in display order.
  - **A set whose entity isn't its key's** is rejected as `malformed`, and no record is written.
  - **A replica** pulling Core's `preferences` partition, two entries a page, holds the same views as Core, the conflict included. The `tasks` partition holds no preference entry.
- **Regressions:** regression package v24 (`m2/make-regressions-v24.py`, v23 plus harness v43; runner `m2/run-regressions-v25.sh`) passes all 31 targets, v35 and v47 among them (`m2/regressions-run-20261126T023013Z/summary.txt`). 21 GB were free.
- **Result: PASS** for Core and the replica. Next, the conversion of `PATCH /v1/preferences` (`R2-CHECKPOINT.md` §11).

### M3-6b, third step, first part: R1's `PATCH /v1/preferences` through the converter (plan §8.12.2, §8.17; R2-TRUST-05; `docs/DECISIONS.md` D-74)

- **Code** (`aa0ec19` → `8313d30`):
  - **`PreferenceRules`** (LisaOwnerData): R1's 24 supported keys; the administrative keys, R1's consequential ones; the permitted keys, which alone replicate; R1's value check.
  - **Core's intake** rejects a device's preference operation as `unsupported_key`, `administrative_key` or `invalid_value`, with no key or value in the reason or hint.
  - **What a converted child observes:** R1's record as Core found it (`resolveFoundRecord`). For a record, the horizon its revision reflects. For an absent key, every commit before the child. `ChangeEntry` serves the horizon on every legacy preference child.
  - **`LegacyChildPlan`:** a child set's IDs, digest and chains from discriminators alone, envelopes encoded when taken in.
  - **`LegacyPreferenceRoutes` and `convertUpdatePreferences`:** `change:<index>` children chained per key; R1's checks in R1's order; the stop at the first refusal; one projection per change, forced for a set or confirm; R1's audit events; R1's full list on success; refusals from templates naming positions; the 409 terminal reply.
- **Full build and R1 suite:** `m3/suite-after-preference-conversion-20261126T025433Z/`: 0 warnings, 0 errors, 376/66. Lint is clean on the nine changed files, apart from R1's own `Package.swift` line 206.
- **Harness:** `m3/harness-v45/`, 10/10 on its first build (`m3/harness-v45-test-20261126T025359Z.log`). v44 is kept, never built. It had a quiet-hours value R1 refuses, and it compared device audit actors across hosts whose device IDs differ.
- **Cases,** each sent to R1's unconverted router on one host and the converting router on another, at one wall clock:
  - **Sets, then a confirm, a set at the record's revision and a delete:** 200 with R1's full list, byte for byte. The records match (value, origin, confirmed, revision, time), and so do the audit events. Every child is `applied`, with `change:0`–`change:2`.
  - **The first refusal stops the request:** a stale `expectedRevision` at change 1 is R1's 409 with current revision 1. R2's message is "changes[1] changed since it was read; reload it and try again". The dispositions are `applied`, `refused`, `not_reached`. A retry replays the refusal on both hosts. Other bytes under the same request ID are 422 on both.
  - **The canaries:** an unknown weekday token, `canaryday`, is R1's 400 on both. R2's answer is "changes[1].value has an unknown weekday", with field `changes[1].value`. An unsupported key, `canary-key-7f3e`, is "changes[0].key is not a supported preference", with field `changes[0].key`. Its confirm is the 404 template. R1's bodies contain the canaries, and R2's don't, nor do its replay, the ledger's served children or the audit events.
  - **A paired device:** an owner-only key is R1's 403 and stops the request ("changes[1] can be changed only by the owner on the host"). A delete is R1's 403. A confirm is applied, one revision step.
  - **Fifty changes to one key:** one chain, each child depending on its immediate predecessor only, with `legacyParent.count` 50. The last value and revision 50 match on both hosts. Fifty-one changes are R1's 400 on both.
  - **A replica:** a set, its delete, a set again and a second key. Every served entry carries Core's horizon, and a replica pulling the partition two entries a page holds Core's views, without conflicts.
  - **An expired reply:** after 31 days, a retry gets the 409 terminal reply, and the record stays at revision 1.
  - **An administrative key in owner scope:** the conversion fails for now (500), keeping nothing, not even the earlier change, until M3-6b's next part adds holds.
  - **Core's device rules:** a device's set of `delivery.emailEnabled` and delete of `model.endpoint` are `administrative_key`, a set of `canary-key-7f3e` is `unsupported_key`, and a set of `brief.time` to `25:99` is `invalid_value`. A permitted set and a confirm are accepted.
  - **A device's set, then R1's blind set** on the owner listener: the converted child replaces the device's value without a conflict, one revision step on.
- **Regressions:** regression package v26 (`m2/make-regressions-v26.py`; runner `m2/run-regressions-v27.sh`) passes all 29 targets, and v35 and v47 pass too (`m2/regressions-run-20261126T025545Z/summary.txt`). 20.6 GB were free.
  - **Its changes from v24:** harness v45 is added, and v43 is replaced by v46. v46 is v43's tests with a permitted key, `planning.bufferMinutes`, where two devices set `delivery.emailEnabled`, which Core now refuses.
  - **Generator v25** is kept, never run. It would have written its runner over the existing `run-regressions-v25.sh`.
- **Result: PASS** for the first part. Next, M3-6b step 3b (`R2-CHECKPOINT.md` §11).

### M3-6b, third step, second part: administrative holds (plan §8.12.2; R2-TRUST-05; `docs/DECISIONS.md` D-75)

- **Code** (`9b09007` → `e920b58`, then `40ec2d7` → `1621ecb`):
  - **`LegacyDecisionToken`** (LisaTrust): the decision key and the `LR-` token.
  - **Schema v12:** the waiting parent's request bytes, and `core_legacy_holds`.
  - **The frame** keeps a conversion that reached a hold, with hold generation 1. `legacyHolds()` lists every hold, each token at its unique length, and `legacyRequestBody` returns the kept bytes.
  - **The preference route:** in owner scope, an administrative key that passes R1's checks holds the request.
  - **The router:** the unrecorded 503, rendered as R1 renders one.
  - **`LegacyPreferenceAnswers`:** R1's request and answer bytes, shared by the router and the coming `resolve`.
- **Full build and R1 suite:**
  - at `e920b58`: `m3/suite-after-holds-20261126T030554Z/`, 0 warnings, 0 errors, 376/66;
  - after the follow-up: `m3/suite-after-preference-answers-20261126T031143Z/`, 0 warnings, 0 errors, 376/66.

  Lint is clean on the changed files, apart from R1's own `Package.swift` line.
- **Harnesses:** each passes on its first build.
  - **`m3/harness-v47/`, 12/12** (`m3/harness-v47-test-20261126T030516Z.log`). It holds v45's tests, with v45's case of an administrative key failing the conversion replaced by the hold, plus the hold's rules.
  - **`m3/harness-v48/`, 12/12** (`m3/harness-v48-test-20261126T031128Z.log`). It is v47 with the hold's first 503 compared with its retry's.
- **Cases:**
  - **An owner-scope request** with an ordinary key, then `delivery.emailEnabled`, an ordinary key and `delivery.callsEnabled`:
    - R1's 503 `unavailable`, `retryAfterSeconds: 300`, with the review message;
    - dispositions `applied`, `held_for_administrative_review`, `pending_behind_review`, `pending_behind_review`;
    - only the first change in R1's records and in the served partition;
    - one hold: index 1, generation 1, waiting, its decision key and an 11-character token as derived;
    - the original bytes kept.
  - **A retry with the same bytes** gets the same 503, headers and body alike, `Retry-After: 300` included, and changes nothing. Other bytes under the request ID get 422.
  - **The decision key and token** against Python's `hashlib` and `base64.b32encode`, for generations 1 and 2, with the typed forms: lower case accepted, too short, outside the alphabet, the wrong prefix.
  - **An invalid administrative value** (`delivery.approvedPhoneNumber` set to "12") is R1's 400 at once on both hosts, with R2's template. The earlier change is kept and nothing holds.
  - **Every case of harness v45** passes unchanged.
- **Regressions:**
  - **Package v27** (`m2/make-regressions-v27.py`, v26 with harness v45 replaced by v47; runner `m2/run-regressions-v28.sh`) passes all 29 targets, v35 and v47 too (`m2/regressions-run-20261126T030608Z/summary.txt`).
  - **Package v28** (v27 with v47 replaced by v48; runner `m2/run-regressions-v29.sh`) passes all 29 targets, v35 and v47 too (`m2/regressions-run-20261126T031158Z/summary.txt`). 20.0 GB were free.
- **Result: PASS** for holds. Next, `resolve` (`R2-CHECKPOINT.md` §11).
