<!-- The owner-verification harness's quick start (plan R2 §10.8). -->
# Lisa owner-verification harness

This harness lets you verify Lisa's Apple apps and named services under your own identity, on your own devices and accounts. Claude builds it, runs its fixture cases and evaluates the redacted exports you choose to share; Claude never operates your devices or accounts. Everything it records stays in `~/LisaVerify/` on your machine.

## Prerequisites

- A clone of this repository (any clean checkout of the commit you are verifying) and Swift 6.2 or later (Xcode 26 on the Mac).
- For Apple sessions: Xcode, XcodeGen 2.46.0 and your Team ID, as in [docs/SETUP-APPLE.md](../docs/SETUP-APPLE.md) §1–§3.
- Nothing else for fixture runs: they use only the harness's own controlled servers on `127.0.0.1` and never contact a provider.

## Quick start

From the repository's root:

```sh
swift run lisa-verify quickstart
```

It creates `~/LisaVerify/config.json5` from [config/owner-verify.example.json5](config/owner-verify.example.json5) (never overwriting yours), runs the Apple preflight and lists the cases. Replace the placeholders in your copy with your own values; secrets are named by `file:` or `keychain:` reference, never written in the file.

**First fixture run** (no account, no device; about a second):

```sh
swift run lisa-verify run --mode fixture
swift run lisa-verify report <run-id>
```

Every case should end `PASS`. These are the harness's own checks (S-24): the action ledger never sends a real action twice, an ambiguous action is retried only after you type the confirmation, the redacted export contains none of the planted canaries, and cleanup removes only what a run created.

**First owner session** (X1): follow [docs/SETUP-APPLE.md](docs/SETUP-APPLE.md). It starts with

```sh
swift run lisa-verify pair-session OV-NEAR-MI-01 --devices mac,iphone --condition shared-wifi
```

## Commands

| Command | What it does |
|---|---|
| `quickstart` | Set up `~/LisaVerify`, run the preflight, list the cases |
| `preflight apple [--app <path>.app …] [--push-environment …] [--device <UDID>]` | Xcode, SDKs, the number of signing identities, connected devices, and each signed app's entitlements, profile and derived identifiers, with the reasons a case would stop |
| `cases [--session X1] [--area NEAR] [--markdown]` | The catalogue ([docs/CASES.md](docs/CASES.md)) |
| `guide <case>` | A case's environment, prerequisites, evidence, expected outcome and steps |
| `run --mode fixture\|device [--case …] [--session …] [--area …]` | A fixture run executes now; a device run is created for your session |
| `pair-session <case> --devices … --condition … [--run <run-id>]` | A paired session: the run ID, the session nonce and each device's role |
| `observe <run-id> <case>[@role] --status pass\|fail --observed "…" [--evidence <file>]` | Record your own observation, with the digest of any evidence file |
| `import-diagnostics <run-id> <file>` | Import a device's exported `results.jsonl` or evidence file |
| `report <run-id>` | Write and print the run's `summary.md` |
| `export <run-id> --redacted <file> [--canaries <file>]` | The only form meant to leave your machine ([docs/RESULTS.md](docs/RESULTS.md)) |
| `resume <run-id>`, `retry <run-id> <case>`, `actions <run-id>`, `authorize-retry <action-id>` | Continue a run, rerun one case, list its logical actions, authorize one further attempt of an ambiguous action |
| `cleanup <run-id>` | Remove the run's local data, nothing else ([docs/CLEANUP.md](docs/CLEANUP.md)) |

Later milestones add the verification Core and host steps (M3), provider cases and setup guides (M7) and the live sessions (M7, M8); each arrives before its session.

## What to send back

After a session: `swift run lisa-verify report <run-id>` to read the summary, then `swift run lisa-verify export <run-id> --redacted ~/Desktop/<run-id>-redacted.json` and share that file. It holds allowlisted fields only: no tokens, credentials, calendar URLs, mail content, prompts with your data, telephone numbers, provisioning material or push tokens; addresses and numbers become per-run aliases and provider references become digests.
