<!-- Handoff report to the owner: Lisa R2 at the move to a new development environment (run 20261124-r2-5462). -->
# Lisa R2 — Handoff report to the owner

**Prepared:** 2026-11-26 by Claude, at your request, in the Docker sandbox `lisa.lab` (run `20261124-r2-5462`). The first version was written at 18:28Z. This one, at about 18:44Z, follows the decisions you gave after it. The future agent's companion is `Handoff.md`, now self-contained. The full record is `R2-CHECKPOINT.md`.

## 1. Summary

- **R2 is paused.** The seventh pause, for quota, came at 2026-11-26T03:29Z with 80% of the window used. Nothing has run since.
  - At 18:00Z: no writer, no build or test, and the guard holds no pending pause, so it won't relaunch anything.
  - The repository is clean at `bf27694`, plus this handoff's commits.
- **Progress:**
  - M0 and M2 are complete.
  - M1 is complete at its boundary, with X1 in your hands.
  - M3 is in progress: M3-0 to M3-5 and M3-6a are done, and M3-6b is mostly done.
  - M4–M9 haven't started.
- **Before you remove `lisa.lab`** (§2), fetch the sandbox's commits. Your host is 106 commits behind, plus this handoff's. X1 attempt 2's fix is among them.
- **Your decisions of 2026-11-26, now recorded:**
  - **The run directory isn't copied,** so `Handoff.md` carries everything the next agent needs: how to rebuild the frozen R1 artifacts, the Apple type-check, the quota tools and the regression harnesses.
  - **The permissions carry over** from `lisa.lab`, except the build-output removal override (§8).
  - **You will commit your preferred test results** before the next agent starts (§6).
- **Runnable owner tests now:** X1 attempt 2, and a one-second harness fixture run (§5–§7).
- **Still yours to decide** (§9): a guard v3, and storage space.

## 2. Before you remove the old environment

1. **Fetch the commits.** The sandbox is a clone-mode workspace: commits stay inside it until you fetch them, and they are lost if the sandbox is removed first.
   - **At the handoff,** your host's `feature/distributive` was at `db89ca1`, and the sandbox held 106 more commits plus this handoff's.
   - **On your host:**

     ```sh
     git fetch sandbox-lisa.lab
     git log --oneline -5 sandbox-lisa.lab/feature/distributive   # the handoff commits on top, then bf27694 and 86307ec
     git merge --ff-only sandbox-lisa.lab/feature/distributive    # with feature/distributive checked out
     ```

     Then push to GitHub if you want them there. Claude never pushes (`CONSTRICTION.md`). The sandbox's Git daemon serves only while the sandbox runs.
2. **The run directory `.tmp/r2/` stays behind,** as you decided. Its tools, harnesses and evidence are lost with the sandbox. The tracked records keep every result they state.
   - **The next agent rebuilds** what it needs from `Handoff.md` §7.
   - **The frozen R1 builds will have new hashes.** The binaries embed their build paths. The source identity must match exactly: the manifest hash `5e0524fc…99b46679` over R1's 872 files at `491c90a`.
   - **Optional:** if you want any of this run's evidence for your own records, ask Claude here for the redacted bundle before you remove the sandbox (`export/make_bundle.py`, served through a port you publish with `sbx port publish lisa.lab 8765:8765`). The next agent doesn't need it.
3. **Housekeeping,** if the sandbox stays up for a while:
   - Stop the guard (`guardctl-v2 stop --reason "environment retired"`).
   - Restore `~/.claude/settings.json` from `.tmp/r2/20261124-r2-5462/usage/settings.json.orig-20261124T0750Z`. That puts back the status line and `StopFailure` hook the quota tools changed.
   - Ask Claude to do it, or do it yourself. With no pending pause, the guard launches nothing meanwhile.
4. **Close a second Claude session,** if it isn't yours: pid 401717, session `eca30a50…`, started 17:55Z with `--agent claude`. It was idle with no child processes, and it has written nothing. Only one writer should ever work in the checkout.

## 3. Repository status

| Item | State |
|---|---|
| Branch | `feature/distributive` |
| HEAD | The commit that adds this file. The pause record is `bf27694`; the code is unchanged since `54c4699` |
| Tree | Clean. Nothing untracked outside the ignored `.tmp/` and `.build/` |
| Last buildable checkpoint | `54c4699`. On the Debian 13 sandbox `lisa.lab`, x86_64, Swift 6.4.2: debug build with tests, 0 warnings, 0 errors; R1 suite 376/66; M3 harness v50 15/15; regression package v30, 29 of 29 targets plus v35 and v47 |
| Schema | Core store migrations up to v13 |
| Plan | `plans/R2.md` revision 13, approved, unchanged |
| Lockfile | `Package.resolved` SHA-256 `f8463195…bc91e776` (swift-crypto 5.1.2, D-53) |

## 4. Project progress

| Milestone | Status |
|---|---|
| M0 Baseline | **Complete.** The R1 suite passes 376/66 in debug and release with Swift 6.4.2 and 6.4.3 |
| M1 Contracts and Apple proofs | **Complete at its boundary;** X1 is with you. Attempt 1 failed at the Xcode build, and attempt 2 is requested at `795b4f3` or later |
| M2 Replication engine | **Complete at its boundary:** a clean reconstruction of `815bbbc` |
| M3 Core, v1 and the direct HTTPS path | **In progress** (below) |
| M4–M9 | Not started. X2–X7 follow their milestones; LS-1–LS-3 follow M7 and M8 |

**M3 so far:**
- **Core:** the ledger, signed change pages and full snapshots, receipts, and the direct HTTPS path with negotiation and body limits.
- **Enrollment and trust:** roster, revocation and key rotation, with S-04 and S-05 over real TLS.
- **Legacy translation,** each route tested against R1's own path on a second host:
  - **`POST /v1/tasks` and `PATCH /v1/tasks/{id}`** go through R2's converter.
  - **`PATCH /v1/preferences`** goes through it too. Its error answers name positions and never echo your text.
  - **Core refuses a device's change to an administrative setting** (R2-TRUST-05).
  - **Administrative holds:** a request that reaches an administrative key on the owner listener waits with R1's 503 and an `LR-` decision token.
  - **Resolve:** the refusal at the administrative terminal records R1's 403 and keeps it permanently.
- **Next:**
  - applying a held change, with a Core-only partition for administrative settings;
  - redacted receipts;
  - the `lisa core legacy` commands;
  - then the remaining v1 routes, backups and restore, firing identity, `lisa core`, and the M3 boundary with X2.

**Not finished, though code exists:**
- **The converter is off,** so production v1 still runs R1's own handlers.
- **"Apply"** at the administrative terminal is deliberately refused for now.
- **Apple code** is type-checked on Linux only and has never been built by Claude.

The requirements' per-ID statuses are recorded at the M3 boundary (`docs/REQUIREMENTS-MATRIX.md`, "R2 (in progress)").

## 5. Runnable owner tests

| Test | Where | You need | What it decides |
|---|---|---|---|
| **X1 attempt 2** | Your Mac, iPhone and iPad; the proof app `Apps/Proof` (scheme `LisaProof`, test plan `X1`), at the fetched head (`795b4f3` or later) | Xcode 26 and XcodeGen 2.46.0; your Apple Developer team with the devices registered; iOS/iPadOS 18 or later. For the no-access-point cells, Wi-Fi and Bluetooth on with no network joined. For E-1, an https URL you control and the controlled names, listener, proxy, NAT64 network (macOS Internet Sharing) and split-tunnel VPN each case's guide names | **E-2** (Apple builds; R2-A01 at X1); **N-1** (which nearby design R2 builds; M6 waits for it); **E-1** (safe public fetches; M7's retrieval design) |
| **Harness fixture run** | Any machine with Swift 6.2 or later, your Mac included | Nothing: the harness's own servers on `127.0.0.1` | The harness's own safety checks (S-24): no real action sent twice, retries only after your confirmation, exports redacted |

**Not runnable yet:**
- **X2,** after M3: it needs `Apps/Probe` and a verification Core you run.
- **X3–X7,** after M5–M9.
- **LS-1–LS-3,** your live provider sessions after M7 and M8.

## 6. Results preferred before resuming

**Resuming M3 doesn't need them:** its remaining work is Linux Core work. Whatever you return is imported when it arrives.

**The X1 results that help most**, in this order:
1. **The builds (E-2: `OV-APPLE-X1-01` Mac, `-02` iPhone, `-03` iPad).** They show whether the line-130 fix and the key-path bindings compile with the real SDK. They also test the Linux stand-in check (D-70) that now runs before every build you're asked to make.
   - **Pass:** the three builds succeed, `lisa-verify preflight apple` prints no line starting "stops:", and the in-app E-2 check passes on each device.
   - **If a build fails,** send the output of `xcodebuild -version` and every error with its file and line, so one fix covers them all.
2. **Test plan `X1`,** the proof app's UI smoke test, passing on the Mac and iOS.
3. **N-1,** the nine nearby cells for each design. A design is adopted only if it passes all nine (three pairs × shared Wi-Fi, Internet disconnected, no access point). M6 waits for this. If both designs fail, nothing is adopted and a redesign comes back to you.
4. **E-1,** the nine fetch cases on each device, with the outcomes listed in §7 step 9. M7's retrieval design waits for this.

**In the new environment,** before writing anything, the agent runs its own acceptance checks: Swift 6.4.2, a debug build with 0 warnings, the R1 suite at 376/66, and the lockfile unchanged. Your permissions let it install the toolchain with the signature-verified recipe.

**Attaching the results** (you said you will commit them before the next agent starts):
- **Commit them on `feature/distributive`,** after the handoff commits, in a folder of your choosing, for example `owner-results/X1-attempt2/`. The agent looks for your commits after the handoff (`Handoff.md` §8).
- **Most useful:** the redacted export (`<run-id>-redacted.json`), the output of `xcodebuild -version`, and the build logs if a build failed.
- **A one-line note** of which design passed on which cells, and anything you saw that the export can't show.
- **Check before committing:** the redacted export is made for sharing, but build logs may hold your Mac user name and local paths. Commit them only if you're comfortable, or send just the error lines.

## 7. Step by step: X1 attempt 2

The full sheet is `Harness/docs/SETUP-APPLE.md`. You can stop after step 5 and send only the build results first.

0. **Fetch the commits** (§2.1). Check out `feature/distributive` at the fetched head on your Mac, and confirm `git log` contains `f03cf24` and `795b4f3`.
1. **Prerequisites:** as in §5. For XcodeGen and signing (`Apps/Config/Signing.local.xcconfig`), see `docs/SETUP-APPLE.md` §1–§3.
2. **The harness:** from the repository's root, run `swift run lisa-verify quickstart`. It creates `~/LisaVerify/config.json5` and runs the Apple preflight. As an optional sanity check, run `swift run lisa-verify run --mode fixture`, then `swift run lisa-verify report <run-id>`; every case should end `PASS`.
3. **Build:**

   ```sh
   cd Apps && xcodegen generate --spec project.yml
   xcodebuild -scheme LisaProof -destination 'platform=macOS' LISA_PROOF_COMMIT=$(git rev-parse HEAD) build 2>&1 | tee ~/LisaVerify/x1-build-mac.log
   xcodebuild -scheme LisaProof -destination 'platform=iOS,id=<iPhone UDID>' LISA_PROOF_COMMIT=$(git rev-parse HEAD) build 2>&1 | tee ~/LisaVerify/x1-build-iphone.log
   xcodebuild -scheme LisaProof -destination 'platform=iOS,id=<iPad UDID>' LISA_PROOF_COMMIT=$(git rev-parse HEAD) build 2>&1 | tee ~/LisaVerify/x1-build-ipad.log
   ```

   If any build fails, stop here and send `xcodebuild -version` and every error, from the logs or Xcode's Report navigator ("All Messages").
4. **Install and check:** install and launch on each device (Product › Run, or `xcrun devicectl device install app`), then run `swift run lisa-verify preflight apple --app <DerivedData path>/LisaProof.app`. Expected:
   - the bundle `org.example.lisa.proof`, or your prefix;
   - one keychain access group;
   - the App Sandbox on the Mac;
   - a development profile listing each device;
   - no "stops:" line.
5. **Record E-2:**
   - Run `swift run lisa-verify run --mode device --session X1` and note the run ID.
   - For each build, run `swift run lisa-verify observe <run-id> OV-APPLE-X1-01 --status pass --observed "LisaProof built for macOS" --evidence ~/LisaVerify/x1-build-mac.log --platform macOS`, and likewise `-02` and `-03`.
   - On each device, in the Results tab, run "Run the portable-module check and write its record".
6. **Test plan X1:** run `xcodebuild test -scheme LisaProof -testPlan X1 -destination …`. If Xcode shows the UI test targets as missing, remove those entries and add `LisaOwnerUITests-iOS` and `LisaOwnerUITests-macOS` once, and note that you did.
7. **The proof roster** (once per installation): label each device (`mac`, `iphone`, `ipad`). On the Mac, "Generate on this device" with "Show setup text", and enter the `lisa-proof-setup:1:` text on the iPhone and iPad. Add every other device's `lisa-proof-card:1:` card on each device. For Design B, run "Provision Design B identity" on each device and re-share the cards.
8. **The nine nearby cells (N-1),** for each design in its own pass. Pairs are `MI`, `MP` and `IP`; conditions `01` shared Wi-Fi, `02` Internet disconnected at the router, `03` no access point.
   - Start a cell with `swift run lisa-verify pair-session OV-NEAR-MI-01 --devices mac,iphone --condition shared-wifi --run <run-id>`, then `swift run lisa-verify guide OV-NEAR-MI-01`.
   - Enter the printed nonce and roles in each device's Results tab.
   - Follow the guide: identification and the hello, the four refusals, reconnection, deduplication, timing, and the local-network permission.
   - Press "Finish cell" on both devices, export `results.jsonl` and `evidence.jsonl` from each, and import every file with `swift run lisa-verify import-diagnostics <run-id> <file>`.
9. **The fetch probe (E-1):** on each device, with Core not configured, run cases `OV-APPLE-X1-FETCH-01`–`09` in the Fetch tab, as each guide says. The passing outcomes:
   - 01, 03, 04, and the public URLs of 05 and 06, are fetched;
   - 02 is refused before connecting, and your listener records nothing;
   - in 06, AAAA-only names and global IPv6 literals are deferred to Core;
   - 07 is never dialed by its AAAA;
   - 08 is on one interface, or fails closed;
   - 09 records the platform facts. Also run the SDK `grep` for `nw_nat64_copy_prefixes_async` from the sheet's §5.
10. **Assumptions:** record any of the sheet's §6 assumptions that fails, with `observe … --status fail`.
11. **Return:**
    - run `swift run lisa-verify report <run-id>`;
    - run `swift run lisa-verify export <run-id> --redacted ~/Desktop/<run-id>-redacted.json`;
    - share the redacted file, and say which design passed on which cells.

## 8. The new environment: permissions and what to provide

**Your decision (2026-11-26):** the permissions are the same as in `lisa.lab`, except the regenerable-build-output removal override. Recorded in `Handoff.md` §3 and `R2-CHECKPOINT.md` §7.
- **Carries over:**
  - setting up the toolchain with the signature-verified recipe, and installing the necessary development prerequisites;
  - a private container engine for development and testing (P-02, P-03, the account-free P-09a);
  - post-freeze dependency changes with their records;
  - quota monitoring: the plan-usage reading, the status-line tap and the `StopFailure` hook in `~/.claude/settings.json`;
  - the replica's ballast release (D-61).
- **Doesn't carry over:** removing regenerable build output. Plan §10.2 holds again, so the agent removes nothing to free space. It builds incrementally into a few shared scratch paths and asks you when space runs low. Plan on at least 25–30 GB free.
- **Unchanged:** P-07 (R1 test changes need your approval), P-08 (conditional), and everything you keep: the host, accounts, devices, the Apple Developer account and live actions.

**What to provide:**
- the fetched repository;
- an environment where these permissions apply (Debian 13 x86_64 matches the old one most closely);
- enough storage;
- your explicit go-ahead to resume.

Without a guard (§9), resumes after quota pauses are yours to start.

## 9. Decisions waiting for you

1. **Guard v3.**
   - **The problem:** this run's resume is manual because Claude Code moved the session to a background job, the daemon's `bg-spare` process with a new session ID. Guard v2 can't verify that kind of fork, so it rejected the pause.
   - **The proposal** (`R2-CHECKPOINT.md` §5): accept a daemon-spawned spare as a lineage fork, on evidence of its process chain back to a lease holder and its continuing transcript.
   - **Your choice:** approve it, or keep resumes manual. Until you decide, nothing weakens the guard's check.
2. **Storage:** with no removal permission, you may need to add space as the run grows (§8).
3. **P-08,** only if N-1 selects Design B: the exact swift-certificates pin.
4. **Still open from earlier** (`R2-CHECKPOINT.md` §5 and §11): reopening the replica at 0 bytes free.
5. **The platform record:** the plan still describes the Fedora host. As before, the new environment will be recorded in a dated environment amendment, not in the plan, unless you say otherwise.

## 10. Other notices

- **Verified nowhere yet:**
  - Apple builds and device behaviour (X1 onward);
  - live services;
  - arm64;
  - a rootless engine and SELinux;
  - Fedora with Swift 6.3.2;
  - E-5 (libxml2 2.15, OpenSSL 4).

  The Linux results are labelled with the sandbox they ran on.
- **Times ahead of the clock:** four temporary file headers stated times 3–8 minutes ahead. This is recorded in `R2-CHECKPOINT.md` §5. Temporary files aren't edited, so the note is the correction.
- **No live action** or external submission was requested or made in this run.

## 11. Your request 3: clearing tracked intermediate files

- **Searched:**
  - tracked file names and the whole history (pause, resume, handoff);
  - content markers of temporary reports;
  - every untracked or ignored file outside `.tmp/` and `.build/`.
- **Found: no Git-tracked temporary pause reports.**
  - **The pause notes:** R2's eight (`pause-20261124T0945Z-c61b62.md` to `pause-20261126T0330Z-1499cd.md`) are in `.tmp/r2/20261124-r2-5462/`. Git ignores that directory, and the notes were kept out of Git by your rule.
  - **R1's old file:** `PAUSE-CHECKPOINT.md` was already removed in R1 (`88d301c`).
  - **The only tracked pause record is `R2-CHECKPOINT.md`,** the required persistent log (R2-DEV-03, O-7). It is kept, as you asked.
- **Removed:** nothing.
- **Not removed:** the pause notes under `.tmp/`. `CONSTRICTION.md` ("Temporary Files") forbids Claude to remove any temporary file there and allows no permission exception. They stay behind with the old sandbox, which you won't copy. To discard them sooner, delete them yourself, or change `CONSTRICTION.md`.
- **Kept, because they aren't intermediate:**
  - `DEVELOPMENT-ENVIRONMENT-REPORT.md`: the old platform's record, with your decisions in §13 and §14;
  - `IMPLEMENTATION-REPORT.md`: R1's report;
  - `Harness/docs/`: the owner harness and the X1 sheet.
