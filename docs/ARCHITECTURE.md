<!-- Components, ownership, data flow and trust boundaries of Lisa R1. -->
# Lisa — Architecture

> This document describes Lisa R1 as built at the end of Phase 9. The full module table with direct dependencies is in `plans/R1.md` §5.1. What was verified, and on which platform, is in `docs/REQUIREMENTS-MATRIX.md` and `IMPLEMENTATION-REPORT.md`.

## Components

| Component (R1 ARCH-02) | Modules | Status |
|---|---|---|
| Domain | `LisaRedaction`, `LisaTime`, `LisaDomain` | Implemented (Phase 1) |
| Secrets and logging | `LisaSecrets`, `LisaLogging` | Implemented (Phase 1) |
| Format and decision engines | `LisaICalendar`, `LisaMIME`, `LisaXML`, `LisaFeeds`, `LisaHTMLText`, `LisaPlanning`, `LisaPolicy`, `LisaMatching`, `LisaRanking`, `LisaBriefComposer`, `LisaInference` | Implemented (Phase 2) |
| Persistence | `LisaPorts`, `CSQLite`, `LisaSQLite`, `LisaStore` | Implemented (Phase 3) |
| Application services | `LisaIngestion`, `LisaReview`, `LisaDelivery`, `LisaAgenda`, `LisaDevices`, `LisaOwnerData`, `LisaApplication`, `LisaCrypto` | Implemented (Phase 4) |
| Runtime, API core, CLI | `LisaConfig`, `LisaRuntime`, `LisaAPIContract`, `LisaAPI`, `LisaClient`, `LisaHost`, `LisaLocalSources`, `LisaDemo`, `LisaFixtures`, `lisa` (`LisaCLI`) | Implemented (Phase 5; Linux) |
| Integrations | `LisaHTTP`, `CCurl`, `LisaCurl`, connectors, `LisaIMAP`, `LisaSMTP`, `LisaTwilio`, `LisaAPNs`, `LisaOpenAICompatible` | Implemented (Phase 6; adapter contracts tested on Linux, live services not run) |
| Network API | `LisaAPIServer`; `LisaClient`'s URLSession transport | Implemented (Phase 7; Linux) |
| Apple applications | `LisaPresentation`, `Apps/` | View models implemented and tested on Linux (Phase 8); the apps are written and syntax-checked with `swiftc -parse` on Linux, not compiled for any Apple platform |

## Time model

All instants are stored as whole milliseconds since 1970 in UTC (D-02). Source time semantics are kept next to them:
- **Timed occurrences** keep their source zone, or a floating-time flag.
- **All-day occurrences** are local date ranges.
- **Deadlines** are either an instant (with its source zone) or a local date (D-05).

Planning and briefing use one IANA zone from the owner settings. `ZoneRules` converts with explicit gap and overlap handling (D-03).

## Persistence

Services depend only on `RecordStore` (in `LisaPorts`); `LisaStore` implements it on SQLite (D-22, D-23). Raw content is stored separately (D-24).

## Application services

- **Facade:** `LisaApplication` is the single entry point for the API router, the CLI and the demo. Each command checks the caller's principal, runs one service operation and then propagates the resulting domain changes:
  - near calendar changes become important-change notifications;
  - closed tasks resolve their notifications and cancel their reminders;
  - planning-relevant changes recompute today's plan;
  - every change ends with a reminder sync.
- **Maintenance cycle:** `runCycle` reviews pending email, re-matches proposals, plans today, syncs and fires reminders, dispatches the brief when due and runs the outbox. Each step persists its own results.
- **Ports:** services reach storage only through `RecordStore`, settings through `SettingsSource` (configuration overlaid with effective preferences, D-30), sources through `SourceConnector`, and transports through the email, call, push and local-notification protocols. Live adapters arrive in Phase 6; until then only dry-run transports exist.
- **Delivery path:** decision → notification occurrence and per-device delivery records in one transaction → leased claim → send-time re-check by the payload owner → recipient enforcement and the call gate → *submitting* recorded → transport → classified result (D-26, D-27).
- **Transactions:** code inside a transaction uses only that transaction (D-34).

## Host, runtime and API (Phase 5)

- **Composition:** `LisaHost` opens in plan §5.2 order:
  1. the data-directory lock;
  2. logging;
  3. the SQLite store;
  4. effective settings (configuration overlaid with preferences);
  5. adapters;
  6. services and the facade;
  7. the runtime;
  8. the router;
  9. the in-process transports.

  Recovery after downtime runs before anything else (D-36).
- **One API path:** every client action goes through `LisaClient`, then `APITransport`, then `LisaAPI` (the router), then `LisaApplication`. The CLI, the demo and the Mac app's embedded mode use the in-process transport as the local owner; paired devices authenticate with their credential. Validation, request identities, revision checks and permissions are identical for both (D-35).
- **Clients:** `LisaClient` depends only on Foundation and the contract, so the iPhone and iPad app can link it. It provides the typed client, the durable offline queue with stable request IDs, the response cache and notification-action handling.
- **Runtime:** `LisaRuntime` holds the single-writer lock and persisted schedules, and runs bounded cycles with isolated source jobs, backoff with jitter, daily maintenance and graceful shutdown (D-36).
- **Configuration:** `LisaConfig` reads a versioned JSON5 file with its own bounded reader. Validation is strict and actionable, unknown keys are reported, secrets are references only, and every delivery channel defaults to a dry run.
- **Offline demonstration:** `LisaDemo`, with `LisaFixtures` rooted at `Fixtures/`, runs DEMO-01 without accounts or network (D-39).

## Network adapters (Phase 6)

Implemented and verified on Linux against scripted test doubles and loopback servers; live services are not verified (`docs/INTEGRATIONS.md`).

| Module | Role | Depends on |
|---|---|---|
| `LisaHTTP` | HTTP client protocol; URL, redirect and address policy; `Retry-After` | Foundation only |
| `CCurl`, `CCurlShim` | System libcurl module map; typed C wrappers and the connect-time address gate | libcurl 8.14.1 |
| `LisaCurl` | libcurl HTTP client (HTTP/1.1, HTTP/2-only), SMTP submission, IMAP session hand-over | LisaHTTP, CCurl, CCurlShim |
| `LisaHTTPSources` | Shared, package-internal support for HTTP document sources (D-42) | LisaTime, LisaRedaction, LisaDomain, LisaSecrets, LisaPorts, LisaHTTP |
| `LisaCalendarFeeds`, `LisaNewsFeeds` | HTTPS calendars; RSS/Atom feeds and owner-initiated page retrieval | LisaHTTPSources, LisaICalendar / LisaHTMLText, LisaPorts |
| `LisaXSource`, `LisaDiscordSource` | X API v2 and Discord REST read adapters | LisaPorts, LisaSecrets, LisaHTTP |
| `LisaIMAP` | Read-only IMAP subset over the libcurl session (M6a) | LisaCurl, LisaPorts, LisaSecrets |
| `LisaSMTP`, `LisaTwilio`, `LisaAPNs` | Email, call and push transports | LisaCurl / LisaHTTP, LisaPorts; LisaMIME (SMTP); LisaCrypto and LisaAPIContract (APNs) |
| `LisaOpenAICompatible` | Chat Completions model provider | LisaInference, LisaSecrets, LisaHTTP |

- **Composition.** `LisaHost` builds the adapters through `HostAdapters`:
  - connectors for every enabled source;
  - the model provider;
  - live transports only for channels set to live.

  `HostDiagnostics` reports their readiness to `lisa doctor`. The platform supplies the network stack (`HostNetwork`), so a test harness can substitute a scripted client; configuration cannot.
- **Dependencies.** No new third-party package. libcurl was already approved (REC-SYS-02), and `Package.resolved` is unchanged.

## Network API (Phase 7)

Implemented and verified on Linux over loopback (`docs/API.md`, D-44, D-45). The companion transport's Apple behavior is unverified, because no Apple build has run yet (`NOT_RUN_ENVIRONMENT`).

| Module | Role | Depends on |
|---|---|---|
| `LisaAPIServer` | NIO HTTP/1.1 server: listeners, native TLS, limits, timeouts, framing rules, graceful shutdown | LisaAPIContract, LisaLogging, swift-nio (NIOCore, NIOPosix, NIOHTTP1), swift-nio-ssl (NIOSSL) |
| `LisaClient` (additions) | `URLSessionTransport` and `HostEndpoint` for the companions; `OwnerEndpointFile` for the CLI's client mode | LisaAPIContract; FoundationNetworking on Linux |
| `LisaHost` (additions) | `HostAPIServer` (device and owner listeners over the one router), `OwnerAccess`, `LoopbackOwnerTransport` (libcurl), `FileModelRequestBudget`, `OwnerPageRetrievalAdapter` | LisaAPIServer, LisaCurl, LisaCrypto, LisaNewsFeeds |
| `LisaApplication` (additions) | `CapturedPageService`: reading a captured link through the `CapturedPageRetrieval` port in LisaPorts (D-46) | LisaPorts, LisaIngestion |

- **Composition.** `lisa serve` opens the host, starts `HostAPIServer`, writes the owner endpoint file and runs the runtime loop. Shutdown runs in reverse: server, runtime, lock (plan §5.2). The server maps each connection to a `RequestOrigin`: device listener → `authenticateHeaders`; a local peer on the owner listener → `loopbackOwner`.
- **Dependencies (REC-DEP-03/04).** `Package.resolved` now pins eight packages. The new ones are swift-nio 2.105.0, swift-nio-ssl 2.37.6 (with vendored BoringSSL), swift-atomics 1.3.1, swift-collections 1.7.6 and swift-system 1.9.0, all under the Apache License 2.0 (swift-atomics, swift-collections and swift-system with the Swift Runtime Library Exception). swift-nio-ssl's vendored BoringSSL is under a combination of the ISC and OpenSSL licenses, as its `NOTICE.txt` states. swift-certificates is not resolved, because only swift-nio-ssl's own tests use it.

## Apple applications (Phase 8)

`LisaPresentation` holds the screens' state and actions as `@MainActor @Observable` view models, so they build and are tested on Linux. It depends only on Foundation, Observation, LisaClient and LisaAPIContract. The SwiftUI apps in `Apps/` only display these models and add the Apple-specific adapters; Linux does not compile them (APPLE-01).

| Part | Contents |
|---|---|
| Companion models | Rundown, brief and speech text, capture, tasks, reminders, pending actions and conflicts, connectivity and cache age, connection and pairing, this device's notification settings |
| Mac models (D-47) | Inbox (proposals and possible tasks to review), ideas, memory (preferences), settings and health (runtime state, sources, delivery modes, model configuration, paired devices and their notification state), brief history |
| Shared rules | Cached data is never shown as current (`LoadState`). Changes go through the durable queue with revision checks, and conflicts are recoverable. Outcomes are truthful: done, queued, unavailable, conflict or failed |
| Shared helpers | Client services and the connection settings, push registration, notification receipts, Siri actions and replies, spoken text (D-48) |
| `Apps/Shared/` (D-48) | Compiled into both apps: Keychain stores, protected storage, host trust (`PinnedServerTrustEvaluator`), the notification bridge, speech, the six App Intents with App Shortcuts, and the notification strings |
| `Apps/` | XcodeGen definition (`Apps/project.yml`), configuration and entitlements (`Apps/Config/`); the SwiftUI apps in `Apps/Companion/` and `Apps/Mac/` |

## Trust boundaries

- **Secrets:** resolved only through `SecretStore`. Configuration and the database hold references, never values (D-08).
- **Logs:** carry only classified metadata (D-09).
- **Untrusted content:** XML and HTML are read by libxml2 with network access and external entities disabled and entity declarations refused (D-12); HTML becomes text with active content removed and links never fetched (D-14). Model prompts wrap source text as untrusted data, and every model result is validated before use (D-19).
- **Outbound delivery:** recipients are enforced by the outbox at send time, independently of content: approved email addresses, the approved phone number after the full call gate, and active paired devices only (D-26, D-28).
- **Devices:** a paired device authenticates with a 256-bit credential the host stores only as a SHA-256 verifier. A push token is accepted only from an authenticated registration, for its own app and an enabled environment, and never authenticates anything itself (D-29).
- **API:** every caller goes through the one router, so authentication, validation, request identities (scoped to the caller) and revision checks are the same in process and over the network (D-35). The network server accepts plain HTTP only on loopback; the owner listener accepts only local peers (D-44).
- **Model suggestions:** the domain treats a model suggestion as the `model` principal. That principal, like any paired device, can never change consequential settings: recipients, call and email enablement, model routing, or the Time Sensitive opt-in.

## Dependencies

`Package.resolved` pins eight packages, all approved in plan §11 (REC-DEP-01, -03, -04, -06) with their transitive dependencies:
- `LisaCLI` uses swift-argument-parser 1.8.2.
- `LisaCrypto` uses swift-crypto 5.1.2 (raised from 5.1.1 in R2 M0 for two security fixes, `docs/DECISIONS.md` D-53), which needs swift-asn1 1.7.4.
- `LisaAPIServer` uses swift-nio 2.105.0 and swift-nio-ssl 2.37.6. swift-nio needs swift-atomics 1.3.1, swift-collections 1.7.6 and swift-system 1.9.0.

All eight are under the Apache License 2.0. swift-argument-parser, swift-atomics, swift-collections and swift-system add the Swift Runtime Library Exception. The BoringSSL that swift-crypto and swift-nio-ssl each vendor is under a combination of the ISC and OpenSSL licenses. The system libraries are linked dynamically: SQLite, libxml2 and libcurl (`docs/SETUP-LINUX.md`).

## Verification

- **Persistent suite:** `Tests/LisaTests/` is one swift-testing target that uses public APIs only (no `@testable`). It imports most libraries directly and reaches the others through them. Its folders group the tests by kind (`Unit/`, `Integration/`, `Recovery/`, `Acceptance/`, `Adapters/`), with test-only helpers in `Support/`; every test is also tagged with its kind, and a few carry two. Each suite is named with its acceptance or requirement ID (R1 §16.1).
- **Controlled substitutes (plan §10):** a scripted transport at the `LisaHTTP` boundary; loopback TLS servers and scripted IMAP and SMTP servers with certificates generated at run time by the `openssl` CLI; a scripted stand-in for Apple's push service under the real `LisaAPNs` adapter; synthetic P-256 keys; synthetic devices with random tokens. The test host's network refuses every other connection.
- **Temporary checks:** the phase-by-phase verification packages stay outside the repository, in the ignored `.tmp/` directory.
