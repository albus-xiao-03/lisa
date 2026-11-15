# Lisa R1 — pause checkpoint after Phase 4

**Status: paused.** On 2026-11-15 the owner changed the full-run instruction: stop when Phase 4 is complete and verified, and wait for an explicit instruction to resume. Phase 4 is complete and verified on Linux. **Phase 5, the later phases and Phase T have not been started.** Do not resume without the owner's explicit instruction.

## Stopping point

| Item | Value |
|---|---|
| Branch | `main` (the only branch used; nothing pushed) |
| Last Phase 4 commit | `86c72a6` — `docs/REQUIREMENTS-MATRIX.md` Phase 4 coverage |
| Checkpoint commit | The commit that adds this file, directly after `86c72a6` |
| Uncommitted changes | None in tracked or untracked repository files |
| Temporary files | `.tmp/` only (ignored by Git, never committed, kept): progress log `.tmp/progress/STATE.md`, temporary verification harness `.tmp/r1-verify/`, logs `.tmp/logs/`, helper scripts `.tmp/tools/`, probes `.tmp/probes/`, scratch builds |

No subagents or other sessions were running at the pause. No background builds or tests are left running.

## Completed phases

| Phase | Scope | Commits | Ends at | Temporary checks |
|---|---|---|---|---|
| Plan and spec corrections | `specs/R1.md` corrections (`9ce1b41`), `plans/R1.md` revision 3 (approved) | 2 | `9c77b71` | — |
| 1 — Foundations | Redaction, time, domain, secrets, logging; first docs | 61 | `fa6872c` | PASS |
| 2 — Pure engines | iCalendar, MIME, XML, feeds, HTML text, planning, policy, matching, ranking, brief composer, inference | 61 | `0af89c1` | PASS |
| 3 — Persistence | Ports, SQLite wrapper, store, migrations v1–v3, backup and restore | 24 | `72b7687` | PASS |
| 4 — Application services | Ports for connectors, transports, settings and token feedback; LisaCrypto; LisaIngestion, LisaReview, LisaDelivery, LisaAgenda, LisaDevices, LisaOwnerData, LisaApplication | 44 | `86c72a6` | PASS |

Total history: 201 commits before this checkpoint. The package now has 29 targets and 163 Swift files under `Sources/`.

## Verification at the stopping point

All runs are on Linux (aarch64, Debian 13) with Swift 6.4.2 (swift-6.4.2-RELEASE), against commit `86c72a6`.

| Check | Command | Result |
|---|---|---|
| Format lint | `swift format lint --recursive Sources Package.swift` | 0 findings |
| Debug build | `swift build` | Succeeded, 0 warnings |
| Release build | `swift build -c release` | Succeeded, 0 warnings |
| Clean debug build (new scratch path; pinned versions resolved from the local SwiftPM cache) | `swift build --scratch-path .tmp/clean-build-p4` | Succeeded from scratch, 0 warnings (10.6 s) |
| Clean release build | `swift build --scratch-path .tmp/clean-build-p4 -c release` | Succeeded from scratch, 0 warnings (15.5 s) |
| Temporary verification | `cd .tmp/r1-verify && swift test` | 76 tests in 13 suites, all passed |

The 76 temporary checks accumulate across Phases 1–4; Phase 4 added 20 of them. They cover:
- the L32 successive-change scenario across a retry and a restart;
- coalescing of pending changes, while delivered changes are never suppressed;
- an acknowledgement on one device suppressing the other device;
- completion, snooze and deadline-change effects on reminders;
- routing with denied permission, a disabled category and quiet-hours deferral;
- a crash after submission and unknown outcomes, which are never resent;
- bounded retry exhaustion;
- the call gate and Time Sensitive levels;
- brief dispatch once per day, approved-only email and the catch-up skip;
- pairing, credentials, push tokens, provider feedback and revocation;
- mail deduplication and failure classification;
- injection resistance;
- calendar refresh safety;
- capture idempotency without a model;
- preference authority;
- export without credentials;
- planning and brief grounding;
- four R1 §16.3 recovery cases: downtime across reminder times, simultaneous brief requests, a stale feed returning with updates, and a timezone change after a plan exists.

The temporary harness is not the persistent test suite. It is verification scaffolding only (CONSTRICTION.md › Tests).

Phase 4 verification found and fixed three defects:
- **Ingestion deadlock.** Settings were read inside a write transaction. The connection now fails fast with `SQLITE_MISUSE` on re-entrant use, and processors read settings before the transaction (D-34).
- **Moved one-off events.** A moved one-off event was reconciled as a removal plus an addition. One-off events now have a stable occurrence key (D-11, amended).
- **Failure boundary.** A source failure in the same millisecond as the last success was not reported as failing (`Source.isFailing`).

## Outstanding limitations

- **Verification scope:**
  - Linux temporary checks only; nothing in Phase 4 was compiled or tested on macOS, iOS or iPadOS;
  - no live account, credential, push, email or call was used;
  - all deliveries ran as dry runs or through a test-only scripted transport inside the harness.
- **Implemented but not yet exercised by any check** (owed to Phase 5 temporary checks or the Phase T suite):
  - `ProposalService` re-matching, review actions and `.ics` export at service level;
  - meeting items becoming proposals, and invitation parts becoming proposals;
  - `NewsBatchProcessor`;
  - `RetentionService.prune`;
  - `SourceRegistry.disable(retainImported: false)`;
  - `DeliveryOutbox.recordReceipt`;
  - the push-rejection path into token feedback (token feedback itself is checked directly);
  - the local-notification transport path.
- **Partial acceptance tests:**
  - L25, L26, L29 and L31 are verified at service level only; their API, client and Apple parts come in Phases 5–8;
  - L22 is partial;
  - L02, L18, L20, L21, L24, L27 and L30 are not started.

  The current status of every row is in `docs/REQUIREMENTS-MATRIX.md`.
- **Composition:** there is no runtime loop, configuration file, API, CLI or demo yet, so nothing runs the services end to end outside the harness (Phase 5).
- **Pairing codes:** they live only in host memory by design (D-29), so a host restart invalidates pending codes. `docs/OPERATIONS.md` (Phase 5) must say so.
- **Dry-run storage:** dry-run captures are kept in memory (`MemoryDryRunRecorder`). A durable recorder for the host is a Phase 5 composition choice.

## Important decisions made in Phase 4

All are recorded in `docs/DECISIONS.md`:

- **D-25:** extra direct dependencies to earlier rows of plan §5.1. The graph stays acyclic.
- **D-26:** outbox processing:
  - send-time re-checks;
  - recipient enforcement independent of content;
  - quiet hours for notifications only;
  - attempt counting;
  - result classification;
  - no silent downgrade from live to dry run;
  - receipts only from devices.
- **D-27:** notification occurrence keys (reminder plus firing instant; subject plus change sequence; brief once per date and zone), suppressed records for ineligible devices, and the 48-hour relevance window for calendar changes.
- **D-28:** a call escalates five minutes after the notification and is re-gated at send time. Time Sensitive never authorizes calls.
- **D-29:** pairing codes, 256-bit device credentials with SHA-256 verifiers, and push-token rules.
- **D-30:** preference formats and authority, and effective settings.
- **D-31:** captures, deletion cascade and invalidation, export format v1, and retention defaults.
- **D-32:** the ingestion runner, mail deduplication and owner addressing, the owner's own note, and calendar reconciliation rules.
- **D-33:** how extraction results map to records, and reprocessing that respects corrections.
- **D-34:** transaction discipline and the fail-fast guard.
- **D-11 (amended):** stable occurrence identity.

## Unresolved blockers and open items

- **Documentation hosts blocked.** developer.apple.com, support.apple.com, curl.se, www.rfc-editor.org, docs.x.com, www.twilio.com and discord.com return the sandbox's "Approval required" response. The owner must review the pending approvals on the host (`sbx policy approval ls`, `sbx policy approval inspect <id>`, `sbx policy approval respond <id> --option <option-id>`). Apple-specific APNs details must be verified against current official documentation before LisaAPNs is implemented (Phase 6, milestone M6b). If access is still blocked then, those parts are reported partial or blocked.
- **Milestones still ahead (Phase 6):**
  - M6a, IMAP feasibility over the libcurl session hand-over (option C), with the conditional swift-nio-imap fallback;
  - M6b, a full local HTTP/2 exchange with `nghttpd` (already installed).
- **Owner-side setup for later phases:** Apple Developer Program enrollment, APNs key and VPN route. Phase 8 uses placeholders only.

## Dependencies

- **In use:**
  - system SQLite 3.46.1 and libxml2 2.9.14;
  - swift-crypto 5.1.1 with the transitive swift-asn1 1.7.4, pinned in `Package.resolved` (`e052b44`).
- **Approved but not yet used:**
  - swift-argument-parser 1.8.2 (Phase 5);
  - libcurl 8.14.1 (Phase 6);
  - swift-nio-imap 0.5.0, only if M6a fails (Phase 6);
  - swift-nio 2.105.0 and swift-nio-ssl 2.37.6 (Phase 7);
  - XcodeGen 2.46.0 (Phase 8).
- **Installed tool:** nghttp2-server 1.64.0 (`/usr/sbin/nghttpd`).

## Resuming with Phase 5 (only after the owner's explicit instruction)

1. **Re-read the governing documents:** `CONSTRICTION.md` (it overrides everything), `plans/R1.md` §8 Phase 5 and §9.1, and this file.
2. **Confirm the starting state:** run `git status`, which should be clean on `main` at the checkpoint commit, then `swift build`.
3. **Add swift-argument-parser.** Add swift-argument-parser 1.8.2 with `exact:` (REC-DEP-01) for the `lisa` target only, and run `swift package resolve`. Show the `Package.swift` and `Package.resolved` changes in the progress report, then commit each file separately.
4. **Implement the Phase 5 deliverables in dependency order (plan §5.1):**
   - `LisaAPIContract`, including the push-payload schema;
   - `LisaConfig`, with `config.example.json5` in which everything is disabled or dry-run by default;
   - `LisaRuntime`:
     - data-directory lock, persisted schedules and a bounded loop;
     - signals and backoff;
     - health reporting;
     - calls to `LisaApplication.recoverAfterDowntime()` at start, then source synchronization plus `ingested(_:)`, and `runCycle()`;
   - `LisaAPI`, the transport-independent router;
   - `LisaHost`, an offline composition with an in-process `APITransport`;
   - `LisaClient`, with offline queue, cache, conflicts and notification actions;
   - `LisaFixtures` with `Fixtures/`, and `LisaDemo`;
   - the `lisa` CLI.
5. **Follow the transaction rule (D-34).** Code inside a store transaction may use only that transaction. Never call `EffectiveSettings`, the raw-content store or another service from inside one.
6. **Write the Phase 5 documents:**
   - `README.md`;
   - `docs/SETUP-LINUX.md`;
   - `docs/OPERATIONS.md`, covering retention settings, pairing codes lost on restart and dry-run capture;
   - `docs/SECURITY.md`;
   - a first `docs/API.md`.
7. **Verify** per plan §8 Phase 5: L24 (extended demo), L01, L02, L22, and the in-process parts of L10, L20, L21 and L30. Also run the checks owed from Phase 4 listed under Outstanding limitations. Then run lint, debug and release builds, and the temporary harness.
8. **Close the phase:** update `docs/DECISIONS.md`, `docs/ARCHITECTURE.md` and `docs/REQUIREMENTS-MATRIX.md`. Make file-level commits, keeping code and documentation separate. Give the progress report.

## Constraints that stay in force

- **Git:** work only on `main`; local commits only. Do not push, reset, clean, stash, amend, or branch.
- **Commits:** one file-level operation per commit, with implementation and documentation in separate commits.
- **Temporary files:** only in `.tmp/`; they are never committed, removed or overwritten to evade removal.
- **Phase T:** the persistent `Tests/` suite must be built independently. Never read, copy, translate, import or derive it from `.tmp/r1-verify`, and keep that harness unchanged during Phase T.
- **Data and delivery:** use synthetic data only, keep no secrets in code, fixtures, docs, logs or Git, use no live accounts, and keep deliveries dry-run.
