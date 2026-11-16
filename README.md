<!-- Lisa: a single-owner personal secretary. What it does, how it is built, its current verification status and where to start. -->
# Lisa

Lisa is a single-owner personal secretary.

## What it does

- Reads the owner's forwarded mail, calendars, news and captures.
- Keeps commitments and ideas with their evidence.
- Plans each day deterministically and composes readable and spoken briefs.
- Reminds the owner on every paired iPhone, iPad and Mac.
- Emails or calls only approved destinations, under explicit rules.

`specs/R1.md` defines the requirements, `plans/R1.md` the implementation plan, and `CONSTRICTION.md` the rules for working on this repository.

## How it is built

- **A portable Swift package.** The engine, adapters, host runtime, API and command-line interface are a Swift package (Swift 6.4.2, Swift 6 language mode). It builds on Linux and macOS.
- **Apple apps.** The iPhone, iPad and Mac apps live in `Apps/`, outside the package graph, and reach the engine only through the versioned API.
- **The authoritative host.** One host owns the data: the Mac app's embedded runtime, or the headless `lisa` executable. Everything is stored locally in SQLite.
- **Dry run by default.** Delivery is a dry run until the owner deliberately enables a live channel.

`docs/ARCHITECTURE.md` describes the components, and `docs/DECISIONS.md` records each design decision.

## Quick start (Linux or macOS)

```sh
swift build
swift run lisa demo --data-dir /tmp/lisa-demo
```

The demo needs no accounts and no network. It uses synthetic, labeled data and sends nothing. Setup details are in `docs/SETUP-LINUX.md`.

## Documentation

| Document | Contents |
|---|---|
| `docs/SETUP-LINUX.md` | Toolchain, system libraries, builds, tests, demo, configuration, headless operation |
| `docs/OPERATIONS.md` | The single-writer host, cycles, recovery, dry runs, retention, backups, logs, limits |
| `docs/SECURITY.md` | Secrets, authorization, untrusted content, network boundaries, what each provider receives |
| `docs/API.md` | The version 1 API: authentication, request identities, errors, pagination, routes, push payload |
| `docs/ARCHITECTURE.md` | Modules, boundaries and their implementation status |
| `docs/DECISIONS.md` | Design decisions with their reasons |
| `docs/REQUIREMENTS-MATRIX.md` | Each requirement's implementation, evidence and verification status |
| `config.example.json5` | A complete, commented configuration with safe defaults |

## Status

Implementation follows the plan's phases. `docs/REQUIREMENTS-MATRIX.md` records what each requirement's evidence actually covers, and on which platform.

Until the Apple platforms and the live integrations have actually been tested, nothing below counts as release-verified:
- The Apple applications are compiled and tested only on a Mac and real devices.
- Live integrations are checked only with the owner's credentials: mail, Apple's push service, Twilio, X, Discord and model endpoints.
