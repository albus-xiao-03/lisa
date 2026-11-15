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
| Application services | `LisaIngestion`, `LisaReview`, `LisaDelivery`, `LisaAgenda`, `LisaDevices`, `LisaOwnerData`, `LisaApplication`, `LisaCrypto` | Phase 4 |
| Runtime, API core, CLI | `LisaConfig`, `LisaRuntime`, `LisaAPIContract`, `LisaAPI`, `LisaClient`, `LisaHost`, `LisaDemo`, `LisaFixtures`, `lisa` | Phase 5 |
| Integrations | `LisaHTTP`, `CCurl`, `LisaCurl`, connectors, `LisaIMAP`, `LisaSMTP`, `LisaTwilio`, `LisaAPNs`, `LisaOpenAICompatible` | Phase 6 |
| Network API | `LisaAPIServer` | Phase 7 |
| Apple applications | `LisaPresentation`, `Apps/` | Phase 8 |

## Time model

All instants are stored as whole milliseconds since 1970 in UTC (D-02). Source time semantics are kept next to them:
- **Timed occurrences** keep their source zone, or a floating-time flag.
- **All-day occurrences** are local date ranges.
- **Deadlines** are either an instant (with its source zone) or a local date (D-05).

Planning and briefing use one IANA zone from the owner settings. `ZoneRules` converts with explicit gap and overlap handling (D-03).

## Persistence

Services depend only on `RecordStore` (in `LisaPorts`); `LisaStore` implements it on SQLite (D-22, D-23). Raw content is stored separately (D-24).

## Trust boundaries (so far)

- **Secrets:** resolved only through `SecretStore`. Configuration and the database hold references, never values (D-08).
- **Logs:** carry only classified metadata (D-09).
- **Untrusted content:** XML and HTML are read by libxml2 with network access and external entities disabled and entity declarations refused (D-12); HTML becomes text with active content removed and links never fetched (D-14). Model prompts wrap source text as untrusted data, and every model result is validated before use (D-19).
- **Model suggestions:** the domain treats a model suggestion as the `model` principal. That principal, like any paired device, can never change consequential settings: recipients, call and email enablement, model routing, or the Time Sensitive opt-in.
