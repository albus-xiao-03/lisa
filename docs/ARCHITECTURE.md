<!-- Components, ownership, data flow and trust boundaries of Lisa R1. -->
# Lisa — Architecture

> Living document. This version covers what exists so far and is completed in Phase 9. The full module table with direct dependencies is in `plans/R1.md` §5.1; this document describes the parts as built.

## Components

| Component (R1 ARCH-02) | Modules | Status |
|---|---|---|
| Domain | `LisaRedaction`, `LisaTime`, `LisaDomain` | Implemented (Phase 1) |
| Secrets and logging | `LisaSecrets`, `LisaLogging` | Implemented (Phase 1) |
| Format and decision engines | `LisaICalendar`, `LisaMIME`, `LisaXML`, `LisaFeeds`, `LisaHTMLText`, `LisaPlanning`, `LisaPolicy`, `LisaMatching`, `LisaRanking`, `LisaBriefComposer`, `LisaInference` | Implemented (Phase 2) |
| Persistence | `LisaPorts`, `CSQLite`, `LisaSQLite`, `LisaStore` | Implemented (Phase 3) |
| Application services | `LisaIngestion`, `LisaReview`, `LisaDelivery`, `LisaAgenda`, `LisaDevices`, `LisaOwnerData`, `LisaApplication`, `LisaCrypto` | Implemented (Phase 4) |
| Runtime, API core, CLI | `LisaConfig`, `LisaRuntime`, `LisaAPIContract`, `LisaAPI`, `LisaClient`, `LisaHost`, `LisaLocalSources`, `LisaDemo`, `LisaFixtures`, `lisa` (`LisaCLI`) | Implemented (Phase 5; Linux) |
| Integrations | `LisaHTTP`, `CCurl`, `LisaCurl`, connectors, `LisaIMAP`, `LisaSMTP`, `LisaTwilio`, `LisaAPNs`, `LisaOpenAICompatible` | Phase 6 |
| Network API | `LisaAPIServer`; `LisaClient`'s URLSession transport | Phase 7 |
| Apple applications | `LisaPresentation`, `Apps/` | Phase 8 |

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

Implemented and verified on Linux over loopback (`docs/API.md`, D-44, D-45). The companion transport's Apple behavior is unverified until Phase 8.

| Module | Role | Depends on |
|---|---|---|
| `LisaAPIServer` | NIO HTTP/1.1 server: listeners, native TLS, limits, timeouts, framing rules, graceful shutdown | LisaAPIContract, LisaLogging, swift-nio (NIOCore, NIOPosix, NIOHTTP1), swift-nio-ssl (NIOSSL) |
| `LisaClient` (additions) | `URLSessionTransport` and `HostEndpoint` for the companions; `OwnerEndpointFile` for the CLI's client mode | LisaAPIContract; FoundationNetworking on Linux |
| `LisaHost` (additions) | `HostAPIServer` (device and owner listeners over the one router), `OwnerAccess`, `LoopbackOwnerTransport` (libcurl), `FileModelRequestBudget` | LisaAPIServer, LisaCurl, LisaCrypto |

- **Composition.** `lisa serve` opens the host, starts `HostAPIServer`, writes the owner endpoint file and runs the runtime loop. Shutdown runs in reverse: server, runtime, lock (plan §5.2). The server maps each connection to a `RequestOrigin`: device listener → `authenticateHeaders`; a local peer on the owner listener → `loopbackOwner`.
- **Dependencies (REC-DEP-03/04).** `Package.resolved` now pins eight packages. The new ones are swift-nio 2.105.0, swift-nio-ssl 2.37.6 (with vendored BoringSSL), swift-atomics 1.3.1, swift-collections 1.7.6 and swift-system 1.9.0, all under the Apache License 2.0 (swift-atomics, swift-collections and swift-system with the Swift Runtime Library Exception). swift-nio-ssl's vendored BoringSSL is under a combination of the ISC and OpenSSL licenses, as its `NOTICE.txt` states. swift-certificates is not resolved, because only swift-nio-ssl's own tests use it.

## Trust boundaries (so far)

- **Secrets:** resolved only through `SecretStore`. Configuration and the database hold references, never values (D-08).
- **Logs:** carry only classified metadata (D-09).
- **Untrusted content:** XML and HTML are read by libxml2 with network access and external entities disabled and entity declarations refused (D-12); HTML becomes text with active content removed and links never fetched (D-14). Model prompts wrap source text as untrusted data, and every model result is validated before use (D-19).
- **Outbound delivery:** recipients are enforced by the outbox at send time, independently of content: approved email addresses, the approved phone number after the full call gate, and active paired devices only (D-26, D-28).
- **Devices:** a paired device authenticates with a 256-bit credential the host stores only as a SHA-256 verifier. A push token is accepted only from an authenticated registration and never authenticates anything itself (D-29).
- **Model suggestions:** the domain treats a model suggestion as the `model` principal. That principal, like any paired device, can never change consequential settings: recipients, call and email enablement, model routing, or the Time Sensitive opt-in.
