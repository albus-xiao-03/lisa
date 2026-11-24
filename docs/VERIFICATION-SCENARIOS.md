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
| S-16 | Size boundaries and bounded dependency release | M1, M3, M6 | M1 part PASS (M1-1, M1-7: budgets, frame header); M3 and M6 parts not run |
| S-17 | SQLite readers, exhaustion and bursts | M2, M3 | Not run |
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

