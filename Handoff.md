<!-- Handoff for the next Claude agent: Lisa R2 after run 20261124-r2-5462, written when the owner moved development to a new environment. -->
# Lisa R2 — Handoff to the next Claude agent

**Prepared:** 2026-11-26T18:25Z by Claude, at the owner's request, in the Docker sandbox `lisa.lab` (run `20261124-r2-5462`).
**State:** R2 is **paused**: the seventh pause, for quota, at 2026-11-26T03:29Z. The owner is moving development to a new environment.
**Do not resume until the owner explicitly says so.** "Check", "verify" and "report" requests are not resume calls.

## 0. Read first, in this order

1. **`CONSTRICTION.md`.** It overrides everything: this file, `plans/R2.md`, every decision and every prompt. If a task needs a prohibited operation, stop that operation and report the conflict.
2. **This file.**
3. **`R2-CHECKPOINT.md`,** the required resumable record (R2-DEV-03, plan §14, O-7):
   - §1 baseline;
   - §5 blockers and environment events;
   - §6 owner sessions;
   - §7 permissions;
   - §8 the last buildable checkpoint;
   - §9 quota and the guard;
   - §11 next steps, with the exact next action.
4. **`plans/R2.md` revision 13,** approved and never edited unless the owner asks:
   - the milestone table (M0–M9, around line 3334);
   - §8.12.2 (v1 translation), the current work;
   - §10 (verification);
   - §14 (the record).
5. **`docs/DECISIONS.md` D-53 to D-76** (D-69 to D-76 are the newest: v1 translation and preferences).
6. **`docs/SYNC-PROTOCOL.md`** (§8, §8a, §8j), **`docs/VERIFICATION-SCENARIOS.md`** (newest entries last) and **`docs/REQUIREMENTS-MATRIX.md`** (the "R2 (in progress)" rows).
7. **`DEVELOPMENT-ENVIRONMENT-REPORT.md`,** the old platform's record; §13 and §14 hold owner decisions.
8. **`Handoff-Report.md`:** what the owner was told at this handoff.

## 1. Repository status at the handoff

| Item | State |
|---|---|
| Branch | `feature/distributive`, the only branch used or consulted (`CONSTRICTION.md`, "History Reference") |
| HEAD | The commit that adds this file. The pause record is `bf27694`, and the code is unchanged since `54c4699` |
| Tree | Clean. Nothing untracked outside the ignored `.tmp/` and `.build/` |
| Last buildable code checkpoint | `54c4699`: debug build with tests, 0 warnings, 0 errors; R1 suite 376/66; M3 harness v50 15/15; regression package v30 all 29 targets plus v35 and v47 (`R2-CHECKPOINT.md` §8) |
| Schema | Core store migrations up to **v13** (`Sources/LisaStore/Migrations.swift`) |
| Plan | `plans/R2.md` revision 13: approved content `1a5a07d`, approval recorded `05b856e` |
| Frozen R1 | `491c90a` (R1's code, tests, fixtures and lockfile at the freeze) |
| Lockfile | `Package.resolved` SHA-256 `f846319595094d9399eccd89f565e571db298f5dab8c46543bcd7d95bc91e776` (swift-crypto 5.1.2, D-53). It must stay unchanged unless the owner approves a dependency change |
| Remote | `origin` is the owner's GitHub repository. Claude never pushes or fetches (`CONSTRICTION.md`) |

**Check before anything else.** At the handoff, the old sandbox was a clone-mode workspace. The owner's host branch was at `db89ca1`, and **106 commits** (plus this handoff's) existed only in the sandbox until the owner fetched them.
- In the new environment, confirm that `git log` contains `bf27694` and the commits that add `Handoff.md` and `Handoff-Report.md`.
- If it doesn't, **stop and tell the owner.** Never recreate lost commits from memory.

## 2. Project progress

| Milestone | Status |
|---|---|
| **M0 Baseline** | Complete. The R1 suite, 376 tests in 66 suites, passes in debug and release with Swift 6.4.2 and 6.4.3. Frozen R1 sources, builds, the client harness and datasets are under `.tmp/r2/20261124-r2-5462/m0/` |
| **M1 Contracts and Apple proofs** | Complete at its boundary. X1 is handed to the owner: attempt 1 failed at the Xcode build, and **attempt 2 is requested at `795b4f3` or later** (`R2-CHECKPOINT.md` §6). No results are imported yet |
| **M2 Replication engine** | Complete at its boundary: a clean reconstruction of `815bbbc` (`docs/VERIFICATION-SCENARIOS.md`, "M2 boundary") |
| **M3 Core, v1 and the direct HTTPS path** | **In progress.** Details below |
| M4–M9 | Not started. Each owner session X2–X7 follows its milestone; LS-1–LS-3 follow M7 and M8 |

**M3 in detail** (`R2-CHECKPOINT.md` §11; `docs/VERIFICATION-SCENARIOS.md`):
- **Done:**
  - M3-0 to M3-3: the frozen fixtures, schema v5 and the Core ledger's intake, Core's signed change pages per partition, full snapshots of unwindowed partitions from Core, and receipts verified on a replica. Bucket snapshots and repairs from Core come with the calendar change feed;
  - M3-4, the direct path over loopback HTTP, with capabilities negotiation (4b) and per-path body limits (4c);
  - M3-5, enrollment, roster, revocation, key and credential lifecycle, challenges, and S-04 and S-05 over real TLS. Left: re-anchoring, with M3-7, and Design B certificates, only if N-1 selects Design B;
  - M3-D61.
- **M3-6a done:** legacy children and the conversion frame (D-67); observed horizons at Core and on replicas (D-69); R1's `POST /v1/tasks` (D-71) and `PATCH /v1/tasks/{id}` (D-72) through the converter, each tested against R1's own path.
- **M3-6b, mostly done:**
  - the preference model (D-73);
  - preferences at Core and on replicas;
  - `PATCH /v1/preferences` converted, with R2-TRUST-05 enforced at Core (D-74);
  - administrative holds with `LR-` decision tokens (D-75);
  - `legacyResolve` with the refusal, its refusal guard and the review description (D-76).
- **M3-6b, left:**
  1. **Step 3c-i with 3b-iii, one slice** (the exact next action, §7 below): the Core-only partition `core-restricted` for restricted preference keys, a 404 for `core-…` partitions on `/v2/changes`, and `apply`.
  2. **Step 3c-ii:** redacted receipts of restricted siblings.
  3. **The CLI:** `lisa core legacy review` and `resolve`.
- **After M3-6b:**
  - M3-6c: captures, receipts, reminder, notification, proposal and plan-block actions. Ideas have no R2 model yet and belong here.
  - M3-6d: terminal replies, the reply dependency index, outcome-only migrated parents, `upgrade_required` on v1.
  - M3-6e: S-01 against the frozen R1 client.
  - M3-7 to M3-11, then the M3 boundary (the R1 suite in debug and release) and X2's handoff.

**Not finished, though code exists.** Never report these as done:
- **The converter is off:** `LisaHost` doesn't enable it, so production v1 still runs R1's handlers.
- **`resolve`'s `apply`** fails on purpose and moves nothing, and a device's confirm of an administrative key fails its conversion (500, nothing kept). Both wait for the Core-only partition.
- **R1's own writers,** such as preference inference, still write R1's records directly. A conversion touching such a record fails (`recordNotProjected`) until migration (M9) or the writer's conversion.
- **The replica** doesn't yet refuse a device's own operation on an administrative key; Core does.
- **Apple code** is type-checked on Linux against framework stand-ins only (D-70). It was never built or run by Claude. X1 is its first Apple build.

## 3. Rules every session keeps (besides `CONSTRICTION.md`)

- **Git:**
  - **Allowed commands:** `status`, `diff`, `log`, `show`, `rev-parse`, `add` and `commit` only. `reset` only with explicit permission.
  - **Never:** push, fetch, pull, branch, checkout, switch, merge, rebase, stash, clean, amend or config.
  - **One file-level operation per commit.** Implementation and its documentation are committed separately.
  - **Message form:** `add:`, `change:`, `remove:` or `record:`, then the path in backticks, ` — what changed (milestone, D-nn)`.
  - **Trailer:** end each message with the attribution trailer the session gives.
- **Temporary files:** everything Claude creates to help its work goes in `.tmp/` at the project root, usually `.tmp/r2/<run-id>/`.
  - **Never** edit in place, overwrite, rename or remove a temporary file, even a harness that failed before its first build.
  - **Write the next version instead:** `harness-vN+1/`, `make-regressions-vN+1.py`, `guard_v3.py`.
  - **Give every retry a new file name.** A `>` or a `tee` onto an existing file is an overwrite.
- **Tests** (P-07): any change to an R1 test or test-support file needs the owner's approval of a request naming the file, the reason and the evidence. Harnesses Claude writes are temporary files. A persistent package-level harness is built only when the owner asks.
- **The owner alone** operates the Mac, iPhone and iPad, the Apple Developer account, provider accounts and every live action. No live external action without explicit permission. Calendar access must be authenticated, private and read-only.
- **P-08:** the swift-certificates pin needs the owner's approval, and only if N-1 selects mutual TLS (Design B).
- **Claims:** label every build or test claim with its platform and environment. Never present Linux results, stand-in type-checks or mocks as Apple, device or live-service verification.
- **The plan stays unchanged.** Platform differences are recorded in reports and in `DEVELOPMENT-ENVIRONMENT-REPORT.md`-style amendments, never by editing `plans/R2.md`.
- **Build output** (owner, 2026-11-25): regenerable build output (`.build`, scratch paths, clean-run `build-*` folders) may be removed, also inside the run directory.
  - **Each removal's report states** the override, the deleted paths with their sizes, and the recovery commands.
  - **Never removed:** sources, logs, exit codes, hashes, harness work directories, fixtures, reports, or the frozen R1 builds under `m0/`.
- **The replica's ballast** may be released so that the replica opens at launch when storage is full (D-61), with the same record.
- **Times:** read `date -u` before writing any time. Four temporary headers ran 3–8 minutes ahead in this run (`R2-CHECKPOINT.md` §5, record notes).
- **One writer at a time:** never work while another Claude session writes in the same checkout.

## 4. Token usage and the auto-resume policy

- **The owner's policy** (2026-11-25): use each five-hour window to about 90%, and never hit the limit by accident.
  - **Keep working past 80%.** Split long spans at safe steps rather than stopping early: a span may continue in the next window.
  - **From about 85%,** start nothing that can't finish by about 90%. Finish or checkpoint the current step.
  - **Then run the pause procedure,** so it ends by about 88–90%.
- **Readings must be genuine:** `.tmp/r2/20261124-r2-5462/usage/usage_read.py --record --label <label>`.
  - **How it works:** it starts a headless Claude Code process that sends only the SDK `get_usage` request, with no prompt and no model call, and records the result in `usage/readings.jsonl`.
  - **When:** take one before each expensive step above 80%.
  - **The watchdog:** `usage/watchdog_v1.py --threshold 85 --max-hours 5`, as a background task.
  - **Never estimate usage** in place of a reading.
- **Costs seen in this run:**
  - solo work, 0.3–0.9 points a minute;
  - a build, harness and regression round, 2–6 points;
  - the pause procedure, 2–4 points;
  - two agents in parallel, 11 points in 4 minutes. Run at most one agent at a time.
- **The pause procedure:**
  1. Finish or checkpoint the step.
  2. Update `R2-CHECKPOINT.md`: the header, §8, §9 and §11.
  3. Write a new pause note, `.tmp/r2/<run>/pause-<UTC>-<rand>.md`, covering the reason with the reading, HEAD, unfinished work, the exact next action, owner checks and evidence.
  4. Run `guard/guardctl-v2 pause --session <session> --reason quota --resets-at <reset> --note <note> --measured '<reading JSON>'`.
  5. Run `guardctl-v2 release`, if this session holds the lease.
  6. Stop the watchdog.
- **Auto-resume runs only through the guard,** never through Claude's `schedule`, `/loop` or scheduled tasks (the owner's rule).
  - **The guard** (`guard/guardctl-v2`) is one detached process. It waits without model calls, confirms the reset with a fresh reading, then launches a resumed session that acknowledges the launch.
  - **Bound to:** the account hash, the sandbox name, the checkout and a session **lineage**.
  - **It rejects** a pause from a session outside the lineage.
- **Out of Git:** guard state, raw telemetry and pause notes always stay out.
- **The guard's gap,** an open decision (`R2-CHECKPOINT.md` §5):
  - Claude Code moved the interactive session to a background job. The job ran as the daemon's `claude bg-spare` process, with a new session ID, which guard v2's `extend-lineage` can't verify.
  - So the seventh pause was rejected, and the resume is manual.
  - A guard v3 that accepts a daemon-spawned spare, with process-chain and transcript evidence, is **proposed and waits for the owner.**
  - **Never fake a lineage,** for example by recording a pause under the parent's session ID. Record the event and leave the resume to the owner.
- **In a new environment:** the reader, watchdog and guard are temporary tools in the old run directory. They hardcode `/home/albusxiao/Projects/lisa/...`, the old account binding and the sandbox name `lisa.lab`.
  - **Re-establish them only with the owner's authorization.** That covers reading plan-usage metadata, and changing `~/.claude/settings.json`'s `statusLine` tap and `StopFailure` hook, as authorized for `lisa.lab` on 2026-11-24 (`DEVELOPMENT-ENVIRONMENT-REPORT.md` §13.3).
  - **Use new versions and a new configuration** (§6).
  - **Until then:** without a guard, pause by hand and tell the owner that the resume is theirs.

## 5. Configuring the development environment

**Permissions first** (`CONSTRICTION.md`, "Development Environment"):
- Use the toolchain the environment provides.
- Never install, replace or upgrade the toolchain or system tools, use `sudo`, or change the host environment without explicit, task-specific permission. The owner's 2026-11-24 permission covered `lisa.lab` only.
- If something is missing, report it and stop the affected operation.

**What R2 needs:**

| Need | Detail |
|---|---|
| Swift **6.4.2** | `.swift-version`; R1's toolchain; the plan's O-3 images `swift:6.4.2-trixie` (`sha256:9733821c…430097`) and `-slim` (`sha256:42571ee8…cccea0d`). On `lisa.lab`: `/opt/swift/swift-6.4.2-RELEASE-debian13`, with 6.4.3 beside it for comparison |
| C toolchain and libraries | The swift-docker 6.4 Debian 13 list: `binutils-gold`, `gcc`, `libstdc++-14-dev`, `libedit-dev`, `libncurses-dev`, `libpython3-dev`, `uuid-dev`. Also `libicu-dev`, `libcurl4-openssl-dev` (libcurl 8.14.1), `libsqlite3-dev` (SQLite 3.46.1), `libxml2-dev` (2.9.14), `pkg-config` and, optionally, `nghttp2-server`. The driver links with `ld.gold` |
| Tools | git; Python 3 for the run's tools; `openssl` for the R1 suite's run-time certificates; tzdata |
| Container engine | For M4 and the container smoke runs. The rootful Docker daemon was authorized inside `lisa.lab` only (`DEVELOPMENT-ENVIRONMENT-REPORT.md` §13.1). A new engine needs the owner's authorization. G2 still needs genuine rootless amd64 evidence |
| Storage | M3 builds and regressions need several GB: the debug build, one harness scratch path and one regression scratch path. `lisa.lab` had 19 GB free |

**The toolchain recipe:** `DEVELOPMENT-ENVIRONMENT-REPORT.md` §11, corrected in §13.2. It extracts with `sudo tar` only after `gpgv` shows a GOODSIG and a VALIDSIG from the pinned primary key `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`. Use it, or adapt it to another OS, only with the owner's permission.

**Acceptance at HEAD,** recorded with the new platform's name:

```sh
swift --version                                                        # Swift version 6.4.2 (swift-6.4.2-RELEASE)
swift package --force-resolved-versions resolve                        # Package.resolved unchanged (SHA-256 above)
swift build --scratch-path .build/r2-run -c debug --build-tests        # 0 warnings, 0 errors
.build/r2-run/out/Products/Debug-linux-$(uname -m)/LisaTests-test-runner --testing-library swift-testing   # 376 tests in 66 suites pass
swift build -c release                                                 # 0 warnings (the M0 baseline)
swift format lint <changed files>                                      # Package.swift line ~207 has R1's own warning
```

Compare with M0 (`R2-CHECKPOINT.md` §4). Not available on `lisa.lab`, and recorded as `NOT_RUN_ENVIRONMENT`:
- Fedora 45 with Swift 6.3.2;
- E-5 (libxml2 2.15, OpenSSL 4);
- arm64;
- rootless engines;
- SELinux.

Record what the new environment can provide.

**`lisa.lab`'s quirks,** which may not carry over:
- `grep` is ugrep, which rejects long context regexes. Use Python for `plans/R2.md` (about 1 MB).
- `time`, `column`, `bc`, `hostname`, the `sqlite3` CLI and `xz` are missing.
- SwiftPM colours its logs, so strip ANSI codes before grepping them (`sed 's/\x1b\[[0-9;]*m//g'`).
- The agent harness blocks a foreground `sleep`, so run long commands as background tasks and wait for their notification.
- `/etc/sandbox-persistent.sh` is sourced before every Bash call.

## 6. The run directory `.tmp/r2/20261124-r2-5462/`

It is ignored by Git and existed only in `lisa.lab`. The owner was asked to copy it, or the redacted bundle, before removing the sandbox (`Handoff-Report.md` §2). What it holds:

| Path | What | Why it matters |
|---|---|---|
| `m0/` | Frozen R1 sources (`r1-src/`, manifest and tree hash), the frozen R1 builds and suite, `frozen-client/` (the client harness, `harness4`), `frozen-datasets/` | S-01 (M3-6e) and S-02 and S-13 (M9) run these. **Their hashes are recorded evidence, so never rebuild or replace them silently** |
| `x1/typecheck-v1/` | The Apple-framework stand-ins and `run-v1.sh [6.4.2\|6.4.3]`, with the negative controls (D-70) | Run before every owner Apple build |
| `m1/`, `m2/`, `m3/` | Temporary harnesses (M2 up to v51, M3 v1–v50), regression generators and packages (newest `m2/make-regressions-v30.py`, runner `m2/run-regressions-v31.sh`), suite runs (`m3/run-suite-v1.sh`), logs | The evidence `docs/VERIFICATION-SCENARIOS.md` cites. The newest harness is `m3/harness-v50` |
| `usage/`, `guard/` | The usage reader, status-line tap and watchdog; guard v1 and v2, its configuration and its append-only live state | The quota policy (§4) |
| `export/` | `make_bundle.py`, the redacted evidence bundle with a canary check, and `serve-bundle.sh` | Copying evidence out |
| `owner/` | The owner's X1 attempt 1 report, with analysis | X1 history |
| `pause-*.md`, `reclaim-*` | Pause notes; build-output removal records | The run's history |

- **If it was restored at the same path:** continue run `20261124-r2-5462`, append-only.
  - Scripts hardcode `/home/albusxiao/Projects/lisa/...`. If the repository path differs, write new versions with the new paths; never edit the old ones.
  - Harness packages reach the repository through the relative path `../../../../..` from `.tmp/r2/<run>/m3/harness-vN/`.
- **If it wasn't restored:** start a new run directory `.tmp/r2/<YYYYMMDD>-r2-<rand>/`. Record in `R2-CHECKPOINT.md` §1 that run `20261124-r2-5462`'s evidence lives in the owner's copy or bundle.
  - **Ask the owner for `m0/`** before S-01. Rebuilt frozen artifacts wouldn't match the recorded hashes.
  - **Regression coverage restarts** from the harnesses you write. Before relying on the converted routes, recreate equivalents of the newest harnesses; the cases are listed in the scenario entries.

## 7. Resuming

**Before anything is written,** all of these must hold:
- The owner has explicitly said to resume.
- `git log` contains `bf27694` and the handoff commits (§1).
- The environment acceptance (§5) passes, or its failures are reported and accepted by the owner.
- A genuine quota reading is available, or the owner has named an alternative.
- No other session writes in the checkout.

**Steps:**
1. **Inspect:** `git status`, `git log --oneline -5`, the header and §11 of `R2-CHECKPOINT.md`, and the newest pause note if the run directory came along.
2. **Record the environment.** Make a dated amendment in the style of `DEVELOPMENT-ENVIRONMENT-REPORT.md` §13 and §14, or a new environment report if the owner prefers. Record the acceptance results in `docs/VERIFICATION-SCENARIOS.md` and the platform in `R2-CHECKPOINT.md` §1. Commit each file separately.
3. **Quota:** take a fresh reading. With the owner's authorization, re-establish the reader, watchdog and guard as new versions (§4).
4. **Record the resume** in `R2-CHECKPOINT.md` §9: the eighth resume, manual, in the new environment.
5. **X1:** if the owner returned results, import and evaluate the redacted export (`R2-CHECKPOINT.md` §6; plan §10.5–§10.6).
   - **N-1** selects a nearby design only from a passed proof, and M6 waits for it.
   - **E-1** decides M7's retrieval design.
   - **E-2:** the Apple builds.
   - **If the build failed again:** fix it, re-run `x1/typecheck-v1/run-v1.sh` (or its next version) and request attempt 3, naming the commit.
6. **The exact next action** (`R2-CHECKPOINT.md` §11, "step 3c-i with 3b-iii, in one slice"):
   1. **The Core-only partition:** `CorePreferenceFold.partition(forKey:)` gives `preferences` for permitted keys and `core-restricted` for administrative and unsupported keys. The fold and the change log use it per key. `/v2/changes` refuses any `core-…` partition with 404 in `Sources/LisaCoreAPI/CoreAPIRouter.swift`, and a future snapshot route keeps the same rule.
   2. **`apply`:** factor `LegacyPreferenceRoutes.update`'s loop so that it can start at the held index with the decision's authority. R1's checks run again, the change doesn't hold again, and it is taken in, projected and audited. Then the suffix runs up to the next administrative key, a new hold at generation + 1, or to the end, answered through `LegacyPreferenceAnswers.answer`. The outcome text names what moved, and R1's domain changes are returned for the caller to propagate.
   3. **A device's confirm of an administrative key** is converted into `core-restricted`, in place of the `restrictedSibling` failure.
   4. **A new harness:** S-03's apply runs (changes 3 and 5 of 7 administrative): `LR-a apply`, then the same command again after a reopen, which replays; `LR-b apply` to the end, with the recorded full list; and the 404.
   5. **Then** the R1 suite, a new regression package and the records.
7. **Then:**
   - step 3c-ii's redacted receipts;
   - the CLI, after finding how a CLI process opens Core's ledger with its signing key (`LisaHost` doesn't open one yet);
   - M3-6c to M3-6e, M3-7 to M3-11, and the M3 boundary;
   - X2 to the owner.

**Every slice follows the same round:**
1. Code, as separate files and commits, with a `D-nn` entry for each decision.
2. The debug build.
3. A new harness version: differential against R1's own path for converted routes, in the newest harness's two-host style.
4. The R1 suite.
5. A new regression package holding every current harness. A harness whose expectation a change supersedes is replaced by a corrected copy.
6. The records: `docs/VERIFICATION-SCENARIOS.md`, `docs/DECISIONS.md`, `docs/SYNC-PROTOCOL.md` when the wire or merge changes, `docs/REQUIREMENTS-MATRIX.md`, and `R2-CHECKPOINT.md` §3, §8 and §11.

## 8. Practices and pitfalls from run `20261124-r2-5462`

- **Never edit Swift sources while a regression runs:** the v35 and v47 packages rebuild from the working tree at its end. Commits are safe, because they don't touch the tree.
- **A harness that fails to compile** is fixed in the next `harness-vN`, never in place, even before its first build. Read the code a harness relies on before writing it, because a mistake costs a new version.
- **Check every generated script's names** (package directory, runner path, targets file) before running it. A generator that would write over an existing runner can't be run, so it gets a new version instead.
- **Typed throws:** a typed-throws `do` block may only contain calls of that error type. Wrap other calls, or use `try?` deliberately.
- **Core's store:** a migration goes in `Sources/LisaStore/Migrations.swift` as the next version. Never change an existing migration.
- **Derived identities** (child IDs, decision keys, preference entity IDs) carry vectors computed with Python's `hashlib`. Keep adding vectors for new derivations.
- **Errors on v1 answers** never echo caller text. They use templates that name positions (§8.12.2; `LegacyPreferenceAnswers.template`).
- **Before quoting a prior result,** check it in the scenario entry and its log. Don't restate it from memory.

## 9. Open items for the owner at the handoff

- **Before the move:** fetch the sandbox's commits, and copy the run directory or the redacted bundle (`Handoff-Report.md` §2).
- **X1 attempt 2** results.
- **The guard v3 decision** (§4).
- **The new environment's authorizations:** the toolchain install if needed, a container engine, quota monitoring and its settings changes, and re-arming a guard.
- **P-08** (conditional, as above).
- **Other decisions** still open in `R2-CHECKPOINT.md` §5 and §11 (for example, reopening the replica at 0 bytes free).
