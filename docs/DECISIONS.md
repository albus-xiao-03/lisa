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

## D-11 — Supported iCalendar subset (CAL-01 documented subset)

- **Components:** `VCALENDAR`, `VEVENT` and `VTIMEZONE` (with `STANDARD`/`DAYLIGHT` observances). `VTODO`, `VJOURNAL`, `VFREEBUSY` and `VALARM` are ignored.
- **Properties:** `UID`, `DTSTART`, `DTEND`, `DURATION`, `SUMMARY`, `LOCATION`, `DESCRIPTION`, `STATUS` (`CANCELLED`, `TENTATIVE`, otherwise confirmed), `TRANSP` (`TRANSPARENT` makes the time free), `SEQUENCE`, `LAST-MODIFIED`, `RRULE`, `RDATE` (DATE or DATE-TIME values), `EXDATE`, `RECURRENCE-ID` (overrides and cancelled instances) and `X-WR-CALNAME`.
- **Time semantics:**
  - UTC (`Z`), IANA `TZID`s, and embedded `VTIMEZONE` definitions, including Windows-style names such as "Eastern Standard Time", evaluated from their own rules.
  - Floating times are interpreted in the zone configured for the subscription.
  - All-day values use `VALUE=DATE`.
  - Day-based durations keep the local time across daylight-saving changes.
- **RRULE:**
  - `FREQ=DAILY|WEEKLY|MONTHLY|YEARLY`, with `INTERVAL`, `COUNT` and `UNTIL`.
  - `BYDAY`, with ordinals for `MONTHLY`/`YEARLY` (relative to the month when `BYMONTH` is present, otherwise to the year).
  - `BYMONTHDAY`, including negative values, plus `BYMONTH`, `BYSETPOS` and `WKST`.
- **Outside the subset:** `FREQ=SECONDLY|MINUTELY|HOURLY`; `BYHOUR`, `BYMINUTE`, `BYSECOND`, `BYYEARDAY` and `BYWEEKNO`; `BYDAY` ordinals with `DAILY`/`WEEKLY`; `BYMONTHDAY` with `WEEKLY`; `RDATE;VALUE=PERIOD`; `RECURRENCE-ID;RANGE=THISANDFUTURE`.
  - These produce a visible warning and mark the calendar's availability uncertain. Only the first occurrence is shown; a series is never silently turned into a one-off event.
  - An unknown `TZID` is interpreted in the floating zone, with a warning and uncertainty.
- **Bounds (`ICalendarLimits`):** input bytes, line length, line count, nesting depth, events, occurrences per event (1,000), total occurrences (20,000) and recurrence iterations (50,000). Hitting one produces a warning and uncertainty.
- **Export:** `.ics` writes UTC `DATE-TIME` or `VALUE=DATE`, with escaped text and 75-octet folding. Importing it into a calendar stays an owner action (EVENT-01).
- **Occurrence identity (amended in Phase 4):**
  - a one-off event (no `RRULE` or `RDATE`) has the stable key `single`, so moving it is reconciled as a change to the same occurrence, not as a removal plus an addition;
  - instances of a series are keyed by their original start, which an override carries as its `RECURRENCE-ID`, so moving one instance keeps its key;
  - an override whose series is not in the feed keeps its `RECURRENCE-ID` key.

## D-12 — XML and HTML parsing hardening (SEC-02)

- **libxml2 options:** `XML_PARSE_NONET`, never `NOENT`/`DTDLOAD`/`DTDATTR`/`HUGE`. A process-wide external-entity loader refuses every load.
- **DOCTYPE handling:**
  - Documents whose internal subset declares entities are refused, which covers entity-expansion attacks.
  - A `DOCTYPE` that only names an external DTD is accepted, but the DTD is never fetched or used.
- **Undefined entity references:** before parsing, these are rewritten outside CDATA and comments. Common HTML names become numeric character references; other names stay visible as literal text.
  - **Evidence:** in Phase 2 verification, libxml2's recovery mode dropped `&nbsp;` together with the following text, the same loss seen with FoundationXML during setup. With the rewrite, the text is kept, and the feed warns how many references were rewritten.
- **Malformed feeds:** read with recovery and labeled "not well-formed", never treated as complete.

## D-13 — Character sets (REC-SYS-04 used)

- **Decoding:** Foundation for UTF-8/16, US-ASCII, ISO-8859-1/2, Windows-1250–1254, Shift_JIS and ISO-2022-JP; platform `iconv` for others, such as EUC-JP, GBK/GB18030, Big5, EUC-KR, KOI8-R, ISO-8859-3…16 and Windows-1255–1258.
- **Unsupported or invalid text:** becomes a visible marker, never silently garbled.
- **Linking:** `iconv` comes from glibc on Linux; on Apple platforms the target links `libiconv`. The macOS link is not verified (`NOT_RUN_ENVIRONMENT`).
- **Evidence:** a sandbox probe showed that Foundation on Linux decodes Windows-1252, ISO-8859-2, Shift_JIS, ISO-2022-JP, UTF-16LE and Windows-1251, but not EUC-JP; `iconv_open("UTF-8", "GBK")` succeeded.

## D-14 — HTML to text

- **Dropped:** scripts, styles, frames, objects, media, forms and images. Images become `[image: alt]` when they have alt text.
- **Links:** collected and never fetched.
- **Layout:** block elements become line breaks, and the output is collapsed and bounded.
- **Fallback:** if libxml2 cannot parse a document at all, the visible tag-stripped text is used, never an empty result.

## D-15 — Deterministic planner details (PLAN-02, PLAN-03)

- **Defaults:**
  - maximum allocation 75% of free time;
  - idea exploration budget 60 minutes a day;
  - default durations 30 minutes;
  - buffer 0 minutes, applied around busy events only when configured; travel time is never invented.
- **Today:** time before `now`, rounded up to five minutes, is unavailable.
- **Reason precedence:** an item that fits nowhere is reported as having no free interval (before its deadline, when it has one) rather than as hitting the allocation cap.
- **Preserved blocks:** locked and completed blocks are kept exactly. Accepted blocks are kept unless they now conflict, in which case they are re-placed with a warning.
- **Rejections:** a rejected suggestion is remembered by subject plus a fingerprint of duration, deadline, priority and date.
- **Evidence:** the §16.2 fixture produced task 09:00–09:30 and idea 09:30–10:00. After the 09:00–09:30 event was added, it produced task 09:30–10:00 and idea 11:00–11:30.

## D-16 — Reminder rules (REM-01, REM-02)

- **Occurrence keys:** include the subject's change sequence, so changing a deadline yields new reminders and makes the old ones obsolete.
- **Newly discovered commitments:** only receive reminders still in the future. If every offset has passed but the deadline has not, a single "soon" reminder is created instead.
- **Date-only deadlines:** reminded only at a configured local time.
- **Once-per-day rules:** overdue reminders at most once per local day (default 09:00), and proposal follow-ups at most once per day.
- **Plan blocks:** reminders 10 minutes before an accepted or locked block.

## D-17 — Urgency, Time Sensitive and calls (CALL-01, NOTIFY-06)

- **Urgent deadline:** confirmed, high or urgent priority, a timed deadline within the window (15 minutes), and the task still active. Model wording never counts.
- **Time Sensitive:**
  - Used only for the reminder category and only with the owner's opt-in.
  - A device can opt out, which downgrades the notification to `active`.
  - It never affects quiet hours, recipients or limits.
- **Calls:**
  - A call requires every CALL-01 condition: enabled, the approved number, confirmed, high priority, the urgency window, still active, an outstanding earlier reminder, outside quiet hours, within daily limits, and not provisional.
  - The decision lists each unmet condition.
  - An earlier reminder counts only if it reached a provider or was presented locally.

## D-18 — Brief composition (BRIEF-01, BRIEF-02, BRIEF-04)

- **Construction:** a deterministic template. Both versions are rendered from the same items, so material items (commitments, deadlines, unresolved events, changes, source failures, uncertainty) always appear in both.
- **Spoken version:** no URLs or identifiers.
- **Source honesty:** "Could not check …" for failing or stale sources is distinct from "Checked, nothing new to report: …".
- **Length:** optional items are dropped by priority to meet the target length (default 220 words); omitted items stay in the full view.
- **Spoken duration:** an estimate, words ÷ words-per-minute (default 150).

## D-19 — Extraction validation (MODEL-02, MODEL-03, MAIL-02)

- **Evidence quotes:** must occur in the content that was sent, ignoring case and whitespace; otherwise the item is rejected.
- **Confirmation:**
  - "confirmed" survives only when the quote comes from the owner's own text, such as the note above a forward.
  - For CC'd or unknown-sender mail, items are never confirmed and never addressed to the owner.
- **Dates:** resolved against the message time and the planning zone; ambiguity stays unresolved with its candidates. Dates outside −1 year … +5 years are rejected.
- **Bounds:** durations 1–1,440 minutes; response at most 64 KiB and 25 items.
- **Repair:** an invalid payload gets one repair request, then the extraction fails.
- **Data sharing:** checked before anything is sent. Remote providers receive minimized text, with email addresses, links and phone numbers replaced.
- **Deterministic provider:** labeled `deterministic-rules`, so its output is never presented as live inference.

## D-20 — Event matching thresholds (EVENT-01)

- **Title similarity:** Jaccard similarity of folded title tokens, with filler words removed.
- **States:**
  - `matched`: the same UID, or similarity ≥ 0.8 with a start within five minutes.
  - `possibleMatch`: similarity ≥ 0.5 on the same local day, or the same start with similarity ≥ 0.3.
  - `notFound`: otherwise.
- **Owner decisions:** dismissed and matched are kept. "Owner reports added" stays until a matching occurrence appears.

## D-21 — News ranking (NEWS-01)

- **Selection:** an item needs an interest match or positive feedback. Muted sources and topics are excluded, and "less like this" items are dropped.
- **Duplicates:** removed by canonical URL (lower-cased host, no `www.`, no fragment, no tracking parameters) and by 80% title-word overlap.
- **Score:** interest matches × recency (24-hour half-life) × source weight × 0.8 for title-only items.
- **Reasons:** each selected item carries a short reason, and title-only items are labeled.

## D-22 — Record storage design (DATA-02, DATA-04, MAIL-02)

- **Records:** each collection is a table of JSON record bodies (`DomainJSON`, millisecond instants) plus the indexed columns its entity declares (`LisaPorts/EntityIndexes.swift`).
- **Queries:** may name only declared fields (plus `id`, `revision`, `updated_at`), and every value is a bound parameter.
- **Deduplication:** unique natural keys enforce it. Examples:
  - per-source email key;
  - occurrence key (source, UID, original start);
  - capture request ID;
  - reminder and notification occurrence keys;
  - delivery idempotency key;
  - device installation and credential verifier.
- **Updates:** succeed only when the stored revision equals the caller's (optimistic concurrency); the stored revision then increases by one.
- **Connection:** one serialized connection per store with `journal_mode=WAL`, `synchronous=FULL` (an outbox intent is durable before any side effect), `foreign_keys=ON` and `trusted_schema=OFF`. The database file is created with mode 0600.
- **Search index:** none in R1. Deleting an item invalidates the generated plans and briefs that referenced it, which are regenerated (DATA-05).

## D-23 — Migrations, backups and restore (DATA-02, DATA-05)

- **Migrations:** append-only SQL, one transaction each, including the `user_version` change.
  - v1: core collections.
  - v2: devices and notification occurrences.
  - v3: idempotency records, plus a `deliveries.payload_key` column backfilled from stored JSON.
- **Before migrating:** an existing database is copied to `<db>.pre-migration-v<n>-<ms>.sqlite`.
- **Failures:** a failed migration rolls back and reports; the database is never recreated or discarded. A database with a newer schema is refused.
- **Schema check:** at open, the code checks that every collection and indexed column it expects exists.
- **Backups:** use SQLite's online backup API and write a manifest (format, schema version, creation time, application version, record counts).
- **Restore:** checks the manifest format, schema version, integrity and the backup's own `user_version`, then moves the current database aside (`.before-restore-<ms>`, never deleted) before copying the backup into place.
- **Evidence (temporary checks):**
  - a v1 database with a delivery migrated to v3, and the backfilled `payload_key` found the record;
  - a broken v4 left the schema at v3, the data intact and no partial tables;
  - `user_version` 99 was refused;
  - restore returned the pre-backup state and kept the replaced file.

## D-24 — Raw content retention (DATA-05)

- **Storage:** raw source bytes (messages, feed documents) live in a separate `raw_content` table, referenced from evidence by `RawContentRef`.
- **Retention:** purging by storage time never touches records, so retention of raw content and of generated records can differ. The settings are documented in `docs/OPERATIONS.md` (Phase 5).

## D-25 — Additional direct dependencies (ARCH-02)

- **Decision:** a few modules declare one more direct dependency than plan §5.1 lists. Each new edge points to an earlier row, so the graph stays acyclic:
  - `LisaMatching` and `LisaInference` → `LisaTime`, for local dates and date resolution;
  - `LisaPorts` → `LisaRedaction`, because a push message carries the device token as `Sensitive<String>`;
  - `LisaReview` → `LisaTime`, and `LisaApplication` → `LisaTime` and `LisaLogging`, for the injected clock and logger.
- **Why:** declaring every imported module keeps the dependency graph explicit; nothing relies on a transitive import.

## D-26 — Delivery outbox processing (REM-03, NOTIFY-03, EMAIL-01, CALL-01)

- **Durability:** a delivery is recorded in the same transaction as its decision. A worker claims due deliveries under a lease and opens a *preparing* attempt. Before any transport call, it durably marks the attempt *submitting*.
- **Send-time re-checks:** the payload owner (`LisaAgenda`) re-derives the content when the delivery is sent. Anything resolved, superseded, snoozed, deleted or expired is suppressed with a reason. The outbox then enforces recipients independently of any content:
  - email: only to owner-approved addresses, and only while email is enabled;
  - calls: only to the approved number, after the full CALL-01 gate;
  - notifications: only to an active, eligible device on its own transport.
- **Quiet hours:** notifications are deferred to the end of quiet hours if they are still valid then, and expire otherwise. Calls are refused by the call gate during quiet hours. Email is not an interruption and is not deferred.
- **Attempts:** every claim that reaches content preparation counts toward the attempt limit, including attempts interrupted by a restart, so a crash loop cannot retry forever. A quiet-hours deferral removes its attempt because nothing was sent.
- **Result classification:**
  - not sent and throttled: retried with exponential backoff and jitter, inside the attempt limit and the validity window;
  - rejected: failed. A rejection that invalidates the recipient deactivates the device token through `DeviceTokenFeedback`;
  - unknown, or a lease that expired while submitting: *outcome unknown*, never resent automatically.
- **No silent downgrade:** a live delivery on a channel without a live transport fails with a configuration reason. It is never captured as a dry run or sent another way.
- **Dry runs:** dry-run captures record the intended recipient, subject and content, but never a device token. They count toward call limits, so dry runs show the same limits as live operation.
- **Receipts:** "confirmed delivered" is set only when a device reports the notification as presented.

## D-27 — Notification occurrences (NOTIFY-01, NOTIFY-03, plan §6.4)

- **Reminder occurrence key:** `reminder:<id>:<firing instant>`. A snoozed reminder fires again as a new occurrence.
- **Important change occurrence key:** `commitmentChange:<subject>:<change sequence>`. It is recorded for changes, cancellations and removals of non-tentative calendar events that have not ended more than an hour ago and start within 48 hours. Changes the owner makes to a task are not notified back to the owner; closing a task resolves its notifications.
- **Brief availability occurrence key:** `brief:<local date>:<zone>`, at most one per day by policy. The same record marks the day's brief as dispatched. A brief missed beyond the catch-up window is recorded as an expired occurrence with an audit event, and nothing is sent.
- **Routing:** every active registration gets a delivery record. A device that cannot receive a notification gets a *suppressed* record with the reason (permission, preferences, category, no active token).
- **Collapse key:** the raw key is stored. The APNs adapter sends a fixed-length digest of it.

## D-28 — Call escalation (CALL-01, REM-01)

- **Queueing:** an urgent confirmed deadline queues the call five minutes after the reminder notification, so an acknowledgement in that window suppresses the call.
- **Gate at send time:** the whole CALL-01 gate is evaluated when the call is sent. The "earlier reminder outstanding" condition comes from stored reminder states, never from a missing push acknowledgement alone.
- **Classification:** the Time Sensitive level never authorizes a call.

## D-29 — Pairing and device credentials (NOTIFY-02, SEC-03)

- **Pairing codes:** live only in host memory for 10 minutes. Each is eight Crockford base-32 characters and single use. Five failed attempts discard every pending code.
- **Credentials:** a 256-bit random credential is shown to the device once. The host stores its SHA-256 verifier and compares in constant time (swift-crypto, REC-DEP-06).
- **Push tokens:**
  - accepted only from an authenticated registration, for a configured topic and environment;
  - the last five replaced tokens are kept;
  - provider "unregistered" reports apply only when their timestamp is newer than the token's registration.
- **Mac app:** its embedded host registers as a local-notification installation.

## D-30 — Preference values and authority (MEM-01)

- **Value formats:**
  - times: `HH:MM`;
  - windows: `[daily|weekdays|weekend|mon,tue…] HH:MM-HH:MM`;
  - quiet hours: one daily range;
  - lists: entries or comma-separated text;
  - phone numbers: E.164;
  - the model endpoint: https or loopback;
  - data sharing: `none`, `local-only`, `extraction-only` or `full`.
- **Exploration frequency:** a frequency of n per week becomes a daily idea budget of duration × n ÷ 7 minutes.
- **Authority:**
  - explicit values replace inferred ones, never the reverse;
  - inferred values take effect only after the owner confirms them;
  - inference is refused for consequential keys;
  - paired devices cannot set consequential keys;
  - model keys configure the host and do not map to owner settings.
- **Effective settings:** the configuration file overlaid with effective preferences, and the `SettingsSource` every service reads.

## D-31 — Captures, deletion, export and retention (IDEA-01, DATA-04, DATA-05)

- **Captures:**
  - idempotent by request ID;
  - an idea is stored verbatim at once, before any interpretation;
  - shared links and text become shared news items under the "Shared by the owner" source. Sharing the same address again (case-insensitive scheme and host, fragment ignored) links to the same item.
- **Deletion:**
  - deleting a capture also deletes its idea, and the reverse;
  - deleting an email or news item deletes its evidence and raw content, and unlinks tasks and proposals, which keep their text;
  - stored briefs drop items that cite deleted records and are marked stale for regeneration;
  - disabling a source states whether imported records are kept; if not, they are deleted with their raw content.
- **Export:** format `lisa-export` version 1, with the schema and application versions. Device credential verifiers and push tokens are never exported.
- **Retention defaults:**
  - raw content: 90 days;
  - final delivery history: 180 days;
  - audit records: 365 days;
  - unshared, unrated feed items: 30 days;
  - zero keeps a category indefinitely;
  - logs rotate by size (D-09).

## D-32 — Ingestion and reconciliation (INGEST-01, MAIL-02, CAL-02, NEWS-01)

- **Runner:**
  - each page is stored in the transaction that advances the cursor;
  - a source counts as freshly synchronized only after its last page;
  - failures are classified on the source, and the cursor stays put;
  - the most recent capability and parse notes are kept on the source.
- **Mail:**
  - deduplicated per source by the stable message key, and by Message-ID;
  - owner addressing comes from the owner's approved addresses: forwarded by the owner, sent by the owner, direct, carbon copy, or unknown sender;
  - the owner's own words (the note above a forward, or the body of a message the owner sent) are stored separately as the only text that can confirm a commitment;
  - attached invitations become event proposals without a model.
- **Calendar:**
  - additions and material changes increase the occurrence's change sequence;
  - only a complete snapshot can cancel missing occurrences, and only inside the expansion window (7 days back, 120 days ahead);
  - a failed or partial retrieval changes nothing it did not see.
- **News:** keys are per source; cross-source duplicates are grouped by ranking.

## D-33 — Extraction results (MAIL-02, EVENT-01, MODEL-03, MODEL-04)

- **Mapping of validated items:**
  - commitments and requests addressed to the owner become tasks, with the item's confirmation;
  - requests also mark the email for attention;
  - meetings become event proposals with their uncertainty;
  - changes and information become attention notes for the brief.
- **Reprocessing:** a task re-extracted from the same evidence with the same title is updated, never duplicated, and fields the owner corrected are left untouched.
- **Without a usable model:** the email waits as "awaiting model" instead of being guessed.

## D-34 — Transaction discipline (DATA-02, OPS-02)

- **Rule:** code inside a store transaction uses only that transaction. Effective settings (which read preferences) and raw content are read or written before or after it; batch processors read settings in their preparation step.
- **Guard:** `SQLiteDatabase` detects use of the connection from inside one of its own transactions on the same thread and fails with `SQLITE_MISUSE`, instead of deadlocking on its lock. Phase 4 verification found exactly this deadlock in ingestion before the rule was applied.
