<!-- Significant implementation decisions and assumptions for Lisa R1, with their evidence. -->
# Lisa — Implementation Decisions

This file records significant architectural choices and assumptions, as R1 §1 requires. The plan (`plans/R1.md`, revision 3) holds the overall design; entries here add the evidence and details settled during implementation. Each entry names the requirements it serves.

## D-01 — Module layout and dependency direction

- **Decision:** the portable package is split into the modules listed in plan §5.1. Every module depends only on modules earlier in that table, so the graph is acyclic. Application services reach persistence and adapters only through protocols in `LisaPorts`; only the composition root (`LisaHost`) names concrete implementations. Apple targets live in `Apps/`, outside `Package.swift`.
- **Requirements:** ARCH-01, ARCH-02, APPLE-01.

## D-02 — Instants are whole milliseconds, built from the reference-date representation

- **Decision:** stored and compared instants are rounded to whole milliseconds. `Date(millisecondsSince1970:)` builds the value from `Date`'s own reference-date interval.
- **Evidence:** during Phase 1 verification, building the same millisecond through `timeIntervalSince1970` produced `816519660.1229999` while ISO 8601 parsing produced `816519660.123` (reference-date seconds). The two instants compared unequal. Building from the reference-date interval yields the nearest representable value, and the check then passed.
- **Requirements:** DATA-02, DATA-03.

## D-03 — Daylight-saving gaps and overlaps follow RFC 5545

- **Decision:** a local time inside a spring-forward gap uses the offset in force before the gap, which moves it later by the gap length. A local time inside a fall-back overlap resolves to the earlier instant unless a caller asks for the later one. `ZoneRules` reports both cases explicitly instead of relying on platform calendar behavior.
- **Evidence:** in America/New_York, 2026-03-08 02:30 resolves to 07:30Z (03:30 EDT), and 2026-11-01 01:30 resolves to 05:30Z (earlier) or 06:30Z (later). Those days are 23 and 25 hours long.
- **Requirements:** DATA-03, CAL-01, PLAN-02.

## D-04 — Ambiguous dates stay unresolved unless an explicit setting settles them

- **Decision:** `RelativeDateResolver` resolves a phrase against a documented reference date: the local date of the source timestamp in its zone. These cases return `ambiguous` with every candidate:
  - "next \<weekday\>";
  - today's own weekday name;
  - numeric dates whose parts are both at most 12;
  - year-less dates that have already passed this year.

  Only the owner settings `numericDateOrder` and `nextWeekday` can settle them.
- **Requirements:** DATA-03 ("keep ambiguous dates unresolved").

## D-05 — Date-only deadlines keep their meaning

- **Decision:** `Deadline.onDate` stores only a local date. Planning uses the end of that local day as a boundary, computed on demand and never stored or displayed as the deadline. Reminders for date-only deadlines need a configured reminder time (REM-02).
- **Requirements:** DATA-03, REM-02.

## D-06 — Typed identifiers, explicit revisions and natural keys

- **Decision:** records use typed random identifiers (`EntityID<Tag>`) and an explicit `Revision`. Deduplication relies on unique natural keys rather than derived identifiers. Examples:
  - an email's `messageKey`, such as `imap:<uidvalidity>:<uid>`;
  - a reminder's `occurrenceKey`;
  - a delivery's `idempotencyKey`;
  - a notification's `occurrenceKey`.

  The keys are enforced by unique indexes in the store.
- **Requirements:** DATA-02, MAIL-02, REM-03, NOTIFY-03.

## D-07 — Notification occurrence identity (plan §6.4, correction of 2026-11-15)

- **Decision:**
  - **Important changes:** each is a new occurrence keyed by `(subject, changeSequence)`. The change sequence increases with every material change.
  - **Collapse keys:** for changes, the collapse key is per subject and category, so a newer change replaces an older one on the device.
  - **Coalescing:** applies only while an occurrence has no submitted delivery.
  - **Brief availability:** keyed by local date and zone, as an explicit one-per-day policy.
- **Requirements:** NOTIFY-03, L32.

## D-08 — Secrets are references; protected files must be owner-only

- **Decision:** configuration holds only `SecretReference` values: `env:NAME`, `file:/path` or `keychain:service/account`.
  - **Protected-file rules:** the protected-file store refuses files other users can read, files the user doesn't own, non-regular files, and files over 64 KiB.
  - **Keychain:** references resolve only where a Keychain store is injected (the Apple applications); elsewhere they report "unsupported" instead of falling back.
  - **Logging:** `Sensitive` values describe themselves as `<redacted>`.
- **Requirements:** SEC-01.

## D-09 — Logs classify every metadata value

- **Decision:** metadata values are `public`, `private` (logged only as a 16-hex-digit FNV-1a fingerprint), `secret` (never logged) or a count. The file sink writes JSON lines, rotates at a size limit and keeps a fixed number of files, so log growth is bounded.
- **Requirements:** OPS-01, OPS-02, SEC-01.

## D-10 — Platform minimums

- **Decision:** macOS 15 and iOS/iPadOS 18, which provide Observation, Synchronization (`Mutex`) and mature App Intents. Language mode is Swift 6, and the toolchain is pinned to 6.4.2 (`.swift-version`).
- **Requirements:** ARCH-01, APPLE-01.
