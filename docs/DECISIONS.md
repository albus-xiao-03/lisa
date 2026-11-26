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
- **Preserved blocks:** locked and completed blocks are kept exactly. Accepted blocks are kept unless they now conflict, in which case they are re-placed with a warning: the block is proposed again at its new time, and the reminder for the old time is cancelled.
- **Revisions:** a recomputation that changes no block, unscheduled item or availability keeps the stored revision. So the warning and the explanation of the last change stay until the plan next changes. The planner's other warnings follow from the blocks, which include the calendar's events, and from availability (Phase T).
- **Availability:** notes on a cancelled occurrence, such as the removal note a complete refresh leaves, do not make the day uncertain (Phase T).
- **Rejections:** a rejected suggestion is remembered by subject plus a fingerprint of duration, deadline, priority and date.
- **Evidence:** the §16.2 fixture produced task 09:00–09:30 and idea 09:30–10:00. After the 09:00–09:30 event was added, it produced task 09:30–10:00 and idea 11:00–11:30.

## D-16 — Reminder rules (REM-01, REM-02)

- **Occurrence keys:** include the subject's change sequence, so changing a deadline yields new reminders and makes the old ones obsolete.
- **Newly discovered commitments:** only receive reminders still in the future. If every offset has passed but the deadline has not, a single "soon" reminder is created instead. This happens only when no offset reminder exists for the deadline, so a commitment whose last offset reminder is due never gets a second one (Phase T).
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
- **Source honesty:** "Could not check …" for failing or stale sources is distinct from "Checked, nothing new to report: …". The owner's own shares ("Shared by the owner") are not a checked source, because nothing synchronizes them, so they appear in neither list (Phase 9).
- **Length:** optional items are dropped by priority to meet the target length (default 220 words); omitted items stay in the full view: the API returns them as the brief's `omittedItems`, and the apps list them under the brief (Phase 9).
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
  - capture request key: the caller and the request ID (`<principal>:<request ID>`, since schema v4; D-35);
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
  - v4: the unique capture `request_id` column holds the caller and the request ID, derived from each stored record, so two callers may use the same ID (D-35).
- **Before migrating:** an existing database is copied to `<db>.pre-migration-v<n>-<ms>.sqlite`.
- **Failures:** a failed migration rolls back and reports; the database is never recreated or discarded. A database with a newer schema is refused.
- **Schema check:** at open, the code checks that every collection and indexed column it expects exists.
- **Backups:** use SQLite's online backup API and write a manifest (format, schema version, creation time, application version, record counts).
- **Restore:** checks the manifest format, schema version, integrity and the backup's own `user_version`, then moves the current database aside (`.before-restore-<ms>`, never deleted) before copying the backup into place.
- **Evidence (temporary checks):**
  - a v1 database with a delivery migrated to v3, and the backfilled `payload_key` found the record;
  - a broken v4 left the schema at v3, the data intact and no partial tables (before the real v4 existed);
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
- **Phase 5 additions**, again only edges to earlier rows or new modules placed before their users:
  - `LisaAPI` → `LisaTime`, `LisaLogging`, `LisaCrypto`, `LisaPorts`, `LisaAgenda`, `LisaDevices` and `LisaOwnerData`, for the types in the facade's signatures and SHA-256 request fingerprints;
  - `LisaRuntime` → `LisaDomain`, `LisaIngestion` and `LisaOwnerData`;
  - `LisaHost` → the service and adapter modules it composes, plus `LisaConfig`, `LisaMIME` and `LisaICalendar` for the configured limits;
  - `LisaDemo` → the modules its scenario drives;
  - `LisaCLI` → `LisaConfig`, `LisaHost`, `LisaClient`, `LisaDemo` and swift-argument-parser.
- **New modules:** `LisaLocalSources` (D-37) sits before `LisaHost`. `LisaFixtures` is rooted at `Fixtures/`, as plan §5.1 says.
- **Why:** declaring every imported module keeps the dependency graph explicit; nothing relies on a transitive import.

## D-26 — Delivery outbox processing (REM-03, NOTIFY-03, EMAIL-01, CALL-01)

- **Durability:** a delivery is recorded in the same transaction as its decision. A worker claims due deliveries under a lease and opens a *preparing* attempt. Before any transport call, it durably marks the attempt *submitting*.
- **Send-time re-checks:** the payload owner (`LisaAgenda`) re-derives the content when the delivery is sent. Anything resolved, superseded, snoozed, deleted or expired is suppressed with a reason. The outbox then enforces recipients independently of any content:
  - email: only to owner-approved addresses, and only while email is enabled;
  - calls: only to the approved number, after the full CALL-01 gate;
  - notifications: only to an active, eligible device on its own transport.
- **Quiet hours:** notifications are deferred to the end of quiet hours if they are still valid then, and expire otherwise. Calls are refused by the call gate during quiet hours. Email is not an interruption and is not deferred.
- **Attempts:** every claim that reaches content preparation counts toward the attempt limit, including attempts interrupted by a restart, so a crash loop cannot retry forever. A quiet-hours deferral removes its attempt because nothing was sent. Both lease recovery and claiming enforce the limit (Phase T):
  - a delivery whose interrupted attempt was its last fails with "the host stopped before it was sent; the attempt limit was reached";
  - a pending delivery that has already used every attempt fails when claimed, with "the attempt limit was reached".
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
- **Gate at send time:** the whole CALL-01 gate is evaluated when the call is sent. The "earlier reminder outstanding" condition comes from stored reminder states and delivery outcomes, never from a missing push acknowledgement alone:
  - a reminder counts only if one of its notification or email deliveries was accepted by a provider or presented locally (D-17, plan §6.8);
  - failed, unknown, pending and dry-run deliveries reached no one, so they never count. When every reminder channel is a dry run and nothing was presented locally, a call is refused.
- **Classification:** the Time Sensitive level never authorizes a call.

## D-29 — Pairing and device credentials (NOTIFY-02, SEC-03)

- **Pairing codes:** live only in host memory for 10 minutes. Each is eight Crockford base-32 characters and single use. Five failed attempts discard every pending code.
- **Credentials:** a 256-bit random credential is shown to the device once. The host stores its SHA-256 verifier and compares in constant time (swift-crypto, REC-DEP-06).
- **Push tokens:**
  - accepted only from an authenticated registration, for a configured topic and environment, and only for the registration's own app: the topic must be the app identifier it paired with, never another configured app's (a 403);
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
  - data sharing: `none`, `localOnly` or `remoteMinimized` (the inference module's `ModelDataSharing` values; corrected in Phase 5).
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
  - idempotent per caller and request ID: another device's capture with the same ID is a new capture (D-35);
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
  - deduplicated by the stable per-source message key, and by Message-ID across all sources (made global in Phase 5, so a message imported through a second source is never stored or extracted twice);
  - owner addressing comes from the owner's approved addresses: forwarded by the owner, sent by the owner, direct, carbon copy, or unknown sender;
  - the owner's own words (the note above a forward, or the body of a message the owner sent) are stored separately as the only text that can confirm a commitment;
  - attached invitations become event proposals without a model;
  - Message-ID duplicates, already stored or earlier in the same batch, are recognized before raw content is kept, so a duplicate leaves no copy that deleting the message could not remove (Phase T). Known limit: if the same message arrives through another source between preparation and commit, or the commit fails, its raw bytes stay until raw-content retention purges them, which never happens when that retention is zero.
- **Calendar:**
  - additions and material changes increase the occurrence's change sequence;
  - only a complete snapshot can cancel missing occurrences, and only inside the expansion window (7 days back, 120 days ahead);
  - a failed or partial retrieval changes nothing it did not see;
  - a local source fails the refresh instead of returning an incomplete snapshot (Phase T): a configured file that is missing or unreadable fails with class `configuration`, and a snapshot file over the size limit fails with class `partial`. Nothing is cancelled either way. Mail directories are incremental, so an oversized message file is skipped there with a visible note.
- **News:** keys are per source; cross-source duplicates are grouped by ranking.

## D-33 — Extraction results (MAIL-02, EVENT-01, MODEL-03, MODEL-04)

- **Mapping of validated items:**
  - commitments and requests addressed to the owner become tasks, with the item's confirmation;
  - requests also mark the email for attention;
  - meetings become event proposals with their uncertainty;
  - changes and information become attention notes for the brief.
- **Reprocessing:** a task re-extracted from the same evidence with the same title is updated, never duplicated, and fields the owner corrected are left untouched. "The same title" is the title the extraction gave the task, which the task keeps as `extractedTitle`, so a task the owner renamed is still recognized (Phase T). Matching compares the stored title, which is at most 200 characters.
- **Without a usable model:** the email waits as "awaiting model" instead of being guessed.

## D-34 — Transaction discipline (DATA-02, OPS-02)

- **Rule:** code inside a store transaction uses only that transaction. Effective settings (which read preferences) and raw content are read or written before or after it; batch processors read settings in their preparation step.
- **Guard:** `SQLiteDatabase` detects use of the connection from inside one of its own transactions on the same thread and fails with `SQLITE_MISUSE`, instead of deadlocking on its lock. Phase 4 verification found exactly this deadlock in ingestion before the rule was applied.

## D-35 — API contract and router (API-01–API-03)

- **Contract:** `LisaAPIContract` depends on Foundation only. It defines every route, request and response type, the error model, pagination, the push-payload schema, and the notification category and action identifiers. Clients never see domain types.
- **Routes:** the API-02 list, plus documented extensions:
  - creating tasks;
  - editing ideas;
  - plan-block actions;
  - listing reminders;
  - notification actions;
  - a proposal's `.ics` file;
  - pairing codes;
  - export.
- **Callers:** the in-process transport is trusted as the local owner. Every other caller authenticates with a device credential (`Authorization: Bearer`), or with the owner credential that the network phase adds. The pairing route is authenticated by its one-time code.
- **Request identities:**
  - every mutation carries `Lisa-Request-ID` (8–128 letters, digits or `._:-`);
  - the ledger keys requests by caller and ID, and fingerprints the method, path, query and body with SHA-256;
  - captures are matched by caller and ID too, so the same ID from two devices makes two captures;
  - a retry replays the recorded answer; reusing an ID for a different request is a 422;
  - definite answers (2xx, 400, 403, 404, 409, 413) are kept for 30 days, while 401, 429 and 5xx are retried for real;
  - the router checks the body size after authentication and inside the ledger, so its 413 is replayed. The network server refuses an oversized body before reading it, so that 413 never reaches the router and is not recorded;
  - concurrent duplicates wait for the first;
  - pairing responses carry a credential or a pairing code, so they are never recorded.
- **Revision checks:** task and idea patches, proposal actions, plan-block actions and device preferences require the revision the client saw; a mismatch is a 409 with the current revision.
- **Limits and errors:**
  - pages of at most 200, with a stable cursor (the last record ID);
  - request bodies of at most 256 KiB;
  - a fixed one-minute window per caller (300 requests; anonymous callers get a tenth);
  - typed error codes with distinct statuses; messages never echo secrets or private content.

## D-36 — Host composition and runtime (ARCH-03, OPS-01, OPS-02)

- **Single writer:** an exclusive `flock` on `<data directory>/lisa.lock`, released by the operating system if the process dies. A second writer fails with the owner's process ID and mode.
- **Startup order:** the host opens in plan §5.2 order, then recovers after downtime: expired leases first, then missed reminders.
- **No silent substitution:**
  - live delivery on a channel without an adapter refuses to start instead of falling back to a dry run;
  - a configured source whose adapter is not in the build is registered and marked unavailable;
  - a missing remote model adapter leaves email "awaiting model".
- **Cycle:**
  - due sources run with bounded concurrency, isolated from each other;
  - failures back off exponentially with jitter, never earlier than a provider's retry-after;
  - then the application cycle runs, and daily maintenance (retention and ledger pruning).
- **Persistence:** schedules persist in `runtime-state.json`, and dry-run captures in `dry-run/captures.jsonl` (owner-only, bounded).
- **Shutdown:** SIGINT and SIGTERM end the loop after the current cycle.

## D-37 — Local directory sources (INGEST-01, CLI-01, DEMO-01)

- **New module:** `LisaLocalSources`, not in plan §5.1, imports local files for `lisa import` and the offline demo:
  - `.eml` mail, read incrementally by file name;
  - `.ics` calendars and RSS/Atom feeds, read as complete snapshots.
- **File handling:** regular files only, without following symbolic links or descending into subdirectories, within the sync limits. An oversized file is skipped with a note.
- **Effect on later phases:** `LisaCalendarFeeds` (Phase 6) therefore covers HTTPS subscriptions only.

## D-38 — Push payload (NOTIFY-04, NOTIFY-06)

- **Source:** keys verified on 2026-11-16 against Apple's "Generating a remote notification" and "Sending notification requests to APNs" (official DocC JSON).
- **`aps` dictionary:** `alert` with `title-loc-key` and `loc-key`, plus `category`, `thread-id`, `sound: "default"`, and `interruption-level` `active` or `time-sensitive`. There are no silent, badge or critical keys.
- **Item titles:** a device that opted in to titles gets the `<CATEGORY>_BODY_TITLED` localization key, with the truncated title as its only `loc-args` value.
- **Custom data:** the `lisa` object holds only a schema version, the kind, and opaque notification and subject identifiers with the subject revision.
- **Size:** payloads stay under 4 KB (4,096 bytes), and collapse identifiers within 64 bytes.

## D-39 — Command-line interface and offline demonstration (CLI-01, DEMO-01, CFG-02)

- **`lisa` commands:**
  - `doctor`, `demo`, `run-once`, `import`, `capture`, `plan`, `brief`, `status`, `export`, `backup` and `restore`;
  - `device` (`pair-code`, `list`, `revoke`), `task`, `reminder`, `proposal` and `preference`.

  `serve` and client mode arrive with the network server (Phase 7).
- **Paths:** the configuration file is `--config`, then `$LISA_CONFIG`, then `~/.config/lisa/config.json5`. `--data-dir` overrides the configured directory.
- **Lock:** every command takes the single-writer lock, so while another runtime owns the directory it exits with code 4 instead of competing.
- **Exit codes:** 0 success, 1 failure, 3 invalid configuration, 4 data directory in use, 5 checks failed, 6 host refused to start, 64 usage error.
- **Client path:** commands act through the owner's in-process client, exactly the path the apps use.
- **Demonstration:**
  - It runs only in a new or empty directory, so it can never touch real data.
  - Its clock is fixed at 2026-11-16 08:00 America/New_York, its identities and fixtures are synthetic and labeled, every channel is dry-run, and extraction uses the rule-based provider.
  - Two synthetic devices pair, register and acknowledge through the same API path real devices use.
  - It restarts once, and fails any check whose evidence is missing.

## D-40 — Defects found and fixed in Phase 5

- **Recurrence durations (CAL-01).** Every repeat after the first was measured from its own start to the series' DTEND, so repeats lasted zero minutes and looked like free time to the planner. Instances now use the series' own duration; overrides and one-off events keep their own.
- **CRLF lines (MAIL-01).** Swift treats `"\r\n"` as one character, so `components(separatedBy: "\n")` did not split it. HTML-converted text kept CRLF, and a `Due:` line in an HTML paragraph never reached its task. HTML text and mail text are now normalized, and line-based readers split on any newline.
- **Feed raw content (DATA-05).** The feed document was stored on every synchronization, even when every entry was already known. It is now kept only when an entry is new.
- **Cross-source duplicates (L05).** Message-IDs were deduplicated per source, so importing a message through a second source stored it, and extracted its commitments, twice. They are now deduplicated across sources (D-32).

## D-41 — HTTP boundary and the libcurl layer (ARCH-01, SEC-02, NOTIFY-04)

- **Modules.**
  - `LisaHTTP` holds the protocol and the policies: requests, responses, classified failures, URL, redirect and address policy, and `Retry-After`. It uses Foundation only; the plan allowed LisaTime, but nothing needed it.
  - `LisaCurl` implements it with libcurl 8.14.1, and adds SMTP submission and the IMAP session hand-over.
  - Adapters depend only on the protocol, so the same code runs against a scripted test double.
- **C boundary.**
  - `CCurl` is the system-library module map. It links `curl` directly, because SwiftPM drops pkg-config's `-isystem` flag.
  - `CCurlShim` exposes plain C types only, so libcurl's declarations come from `CCurl` alone. It wraps the variadic `curl_easy_setopt` and `curl_easy_getinfo`, and holds the callbacks for address checks, cancellation and socket waits.
- **Address checks (SEC-02).**
  - Every resolved address is checked in `CURLOPT_OPENSOCKETFUNCTION` before a socket opens. The connected address is checked again in `CURLOPT_PREREQFUNCTION` before any request byte is sent, which also covers reused connections.
  - Address classes follow RFC 6890. IPv6 is allowed only within `2000::/3`, minus documentation, 6to4 and protocol blocks. IPv4-mapped and NAT64 (RFC 6052) addresses are judged by their IPv4 part.
  - `publicOnly` is the default. `allowLocalNetworks` applies only to an endpoint configured with a loopback or private literal or `localhost`. `loopbackOnly` is the only policy that allows plain http, for a model server on the same machine.
  - Link-local addresses, including cloud metadata, are refused under every policy.
  - The live IANA registry needed a sandbox approval, so RFC 6890 was used.
- **No proxy.** `CURLOPT_PROXY` is the empty string, so proxy environment variables are ignored. Behind a proxy, the address Lisa checks would be the proxy's.
- **TLS.**
  - TLS 1.2 or later is required (libcurl 8.14.1 itself allows TLS 1.0). Peer and host verification are always on, against the system trust store.
  - `trustStorePath` replaces the trust store only for loopback verification against a synthetic CA. The host never sets it from configuration.
- **HTTP/2-only requests (NOTIFY-04).**
  - They use `CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE` instead of the plan's `2TLS`. With `2TLS`, libcurl falls back to HTTP/1.1 and may already have sent the request before the version can be checked. With prior knowledge over HTTPS, libcurl 8.10.0 and later offer only `h2`.
  - `CURLINFO_HTTP_VERSION` is checked after every exchange. HTTP/2-only requests need libcurl ≥ 8.10.0 with HTTP/2, checked at run time; without that they fail as unsupported before anything is sent.
  - libcurl still speaks h2 to a TLS server that selects no ALPN protocol at all. Such an exchange fails and is reported as possibly sent (seen on loopback).
- **Sent or not.**
  - A failure counts as "may have been sent" once the pre-request check has passed or any response byte has arrived.
  - libcurl silently resends a request on a new connection when a reused one dies without a response (curl 8.14.1 `transfer.c`). The gate therefore lets POST and PATCH go out at most once per exchange. A refused resend is reported as a lost connection after sending, so the outcome is unknown and never resent automatically.
  - The harness shows that libcurl does resend a GET in that situation, and that a POST is sent once.
- **Limits.**
  - Body and header sizes are enforced in the write and header callbacks.
  - Total and connect timeouts apply, and cancellation works through the progress callback.
  - Headers containing CR, LF or NUL, and malformed header names, are refused, because libcurl sends header strings verbatim.
- **Redirects.**
  - libcurl never follows redirects itself. `HTTPRedirects` follows them only when the request allows it, and re-validates every hop with the URL policy.
  - Methods are rewritten per RFC 9110 §15.4. Credentials are dropped when a hop leaves the origin.
- **Threads.** Each blocking libcurl call runs on its own thread, never on Swift's cooperative pool. A handle is never shared between threads; idle handles and their connections are pooled and reset.
- **Mail.**
  - IMAP and SMTP use implicit TLS or required STARTTLS (`CURLUSESSL_ALL`); there is no plaintext mode.
  - Authentication uses libcurl's negotiation over the verified connection. Forcing `AUTH=PLAIN` would remove IMAP's `LOGIN` fallback (`lib/imap.c`).
  - libcurl sends no LOGOUT when cleaning up a connect-only session (M6a), so LisaIMAP sends its own. The EHLO name is always set, so this machine's host name is never sent.

## D-42 — Network adapters (CAL-01, NEWS-01–NEWS-03, MAIL-01, MAIL-02, EMAIL-01, CALL-01, MODEL-01, NOTIFY-04)

- **Shared source support.** `LisaHTTPSources` is a module added to the plan, with `package` access. It holds the address resolution (public URL or a secret read at use time), the conditional-request cursor, representation headers, status classification and the pass deadline. Its first versions were duplicated in both feed modules; one copy replaced both.
- **Calendar and news feeds.**
  - Requests are conditional GETs (ETag and Last-Modified), limited to public addresses, following at most three re-validated redirects.
  - A 304 changes nothing: it is never a snapshot, so no event is removed.
  - Validators expire after 6 hours (calendars) and 24 hours (news), forcing a full download.
  - Content is checked before ingestion. Private addresses never appear in errors.
- **Owner-initiated retrieval (NEWS-01, SEC-02).**
  - `OwnerPageRetriever` fetches a link the owner or a paired device captured: one https GET, public addresses only, text through LisaHTMLText, no subresources.
  - Apple News items and links found in content are never fetched.
  - It was connected to the capture workflow in Phase 7 (D-46).
- **X.**
  - Reads a selected account through API v2 with an app bearer token, with a `since_id` cursor and bounded pagination.
  - The OpenAPI spec names the fields parameter `post.fields`, while the guides and changelog say `tweet.fields`. Lisa sends `tweet.fields` from one place; this needs a live check.
  - The first synchronization reads only the newest page.
- **Discord.**
  - Reads a channel through REST API v10 as a bot, with an `after` cursor and rate-limit gates.
  - Messages withheld by the `MESSAGE_CONTENT` intent are never stored as empty posts. A capability note explains them, or the source fails as `capabilityDenied` when nothing is readable.
- **IMAP (M6a passed: option C).**
  - Lisa sends only `EXAMINE`, windowed `UID SEARCH`, a size-only `UID FETCH`, `UID FETCH … BODY.PEEK[]` and `LOGOUT`. The size probe and LOGOUT were added to the plan's list.
  - EXAMINE must report `READ-ONLY`. The cursor is (UIDVALIDITY, last UID); a UIDVALIDITY change resynchronizes, with duplicates removed by Message-ID.
  - Oversized messages are named, not downloaded. A message missing in the middle of a pass stops the cursor before it.
  - All seven checks of plan §7.3 passed against a synthetic loopback server. A live mailbox is not tested.
- **SMTP.**
  - Messages are composed with LisaMIME and submitted with `CurlSMTPSubmission`.
  - Results:
    - authentication failure → `rejected`, because repeated failed logins risk lockouts;
    - missing or failed TLS, or a connection failure → `notSent`;
    - 4xx → `temporarilyUnavailable`;
    - 5xx → `rejected`;
    - any failure after the complete message was handed over → `unknown`.
  - Non-ASCII subjects are shortened to about 39 bytes, because LisaMIME writes one unfolded encoded word.
- **Twilio.**
  - One Calls request with inline TwiML: escaped `<Say>`, never `Url`, at most 4,000 characters.
  - Results: 2xx → `accepted` with the call SID; 429 → `throttled`, which Twilio documents as unprocessed; other 4xx → `rejected`; 408 → `temporarilyUnavailable`.
  - 5xx and failures after the request was sent are `unknown`, because call creation has no idempotency key.
- **APNs (M6b passed).** The plan's §6 details were checked against Apple's pages. The differences, now implemented:
  - only `ExpiredProviderToken` regenerates the token (`InvalidProviderToken` is a configuration rejection);
  - 5xx responses are retried no sooner than 15 minutes later (`temporarilyUnavailable`);
  - every 410 invalidates the token, and its timestamp is in milliseconds;
  - priority is 10 for time-sensitive or actionable categories and 5 otherwise;
  - each environment may have its own key;
  - offline storage keeps one notification per app, "in most cases" the latest.

  On loopback, a real HTTP/2 exchange with nghttpd and the transport's exact headers and body were verified, and the JWT was checked with `openssl dgst -verify`.
- **OpenAI-compatible model.**
  - Sends Chat Completions with `model`, `messages`, `max_tokens` (switchable to `max_completion_tokens`), a clamped `temperature`, the `json_object` response format and `stream: false`.
  - The address policy and the model's location come from the endpoint, and no redirects are followed.
  - Minimization and validation stay in the extraction pipeline, as before.
- **Host composition.**
  - `SourceAccess` names each network source.
  - `HostAdapters` builds connectors, the model provider, and live transports only for channels set to live. A live channel whose adapter is missing or unusable stops startup.
  - `HostDiagnostics` reports readiness for `lisa doctor` without contacting any service.
  - The platform supplies the network stack (`HostNetwork`); harnesses inject a scripted client this way.

## D-43 — Defects found and fixed in Phase 6

- **Floating times (CAL-01).** Calendar reconciliation ignored each source's configured floating zone and always used the owner's zone. The processor now takes the source's zone.
- **Unchanged feeds.** An empty, non-snapshot batch (a 304) added the warning "not a complete snapshot"; it no longer does.
- **Secret store reflection (SEC-01).** Printing or dumping an `EnvironmentSecretStore` could show every environment value. Its description and mirror now show nothing.
- **Loopback policy.** `loopbackOnly` refused loopback and allowed public addresses; IPv6 literals kept their brackets, so `http://[::1]` was refused. Both are fixed.
- **Duplicate sends (external actions).** libcurl's automatic resend of POST requests is refused (D-41).
- **SMTP outcome.** A connection lost after the whole message was sent was reported as "not complete". It is now unknown.
- **Temporary provider failures.** APNs 5xx responses were recorded as "throttled by the provider". `TransportResult.temporarilyUnavailable` now carries the provider's reason and retry time.
- **Device tokens.** Registration assumed 32–200 characters and accepted fullwidth digits. It now accepts ASCII hexadecimal of any even length up to 1,024.
- **Private data in descriptions.** HTTP requests and headers now redact credentials and show only method, origin and header names. MIME's invalid-address error no longer contains the address.
- **libcurl cleanup.** libcurl can call back into Lisa from `curl_easy_cleanup`, so cleanup is now explicit while the callback state is still alive. Returned handles are reset first.

## D-44 — Network API server, local client mode and the model request budget (API-01–API-03, ARCH-03, CLI-01, MODEL-01)

- **Server.** `LisaAPIServer` serves HTTP/1.1 with swift-nio 2.105.0 and swift-nio-ssl 2.37.6, handling one request at a time per connection. It depends on `LisaAPIContract` only, not on `LisaAPI` as the plan's module table says; `LisaHost` maps each connection to the router's `RequestOrigin`, so the server holds no application types.
- **Two listeners.**
  - The device listener is at `api.bindAddress` and `api.port` (default `127.0.0.1:8765`).
  - The owner listener is on `127.0.0.1` with a free port, for the CLI in client mode.

  Plain HTTP is allowed only on loopback; any other address needs native TLS or a trusted reverse proxy. The configuration validator checks this, and the server checks it again. Bind addresses must be IP literals and are never resolved.
- **Authentication per listener.**
  - The device listener accepts device credentials, and pairing codes on `POST /v1/devices/pair`. It never accepts the owner credential, whatever the peer's address.
  - The owner listener accepts only the owner credential, and only from loopback peers.
  - Loopback is decided on raw address bytes, including IPv4-mapped IPv6 peers (NIO's sockets are always dual-stack). Behind a reverse proxy, no peer counts as local.
- **The owner credential.**
  - It is issued for each `lisa serve` run: 256 random bits, kept in memory only as a SHA-256 digest, compared in constant time and revoked at shutdown.
  - `lisa serve` writes it with the owner port to `<data directory>/run/owner-endpoint.json` and removes the file at shutdown. The file is mode 0600 in a 0700 directory, replaced atomically, and refused when other users can read it.
  - Client mode uses the file only when its process ID matches the owner of the data-directory lock, so a stale file is never used.
- **Client mode uses libcurl.** The CLI connects through `LoopbackOwnerTransport`:
  - only to 127.0.0.1, enforced by connect-time address checks;
  - with no proxy and no redirects;
  - with the Authorization header marked sensitive.

  The CLI is host-side code, so it uses the host's network stack (plan §5). The URLSession transport is for the companion apps (D-45).
- **TLS.**
  - The minimum is TLS 1.2; NIOSSL's default is 1.0.
  - TLS 1.2 is limited to ECDHE key exchange with AES-GCM or ChaCha20-Poly1305. The default list also offers RSA key exchange and CBC suites. TLS 1.3 uses BoringSSL's fixed suites.
  - ALPN is `http/1.1`; there are no client certificates and no renegotiation.
  - Encrypted private keys are refused at start-up, because BoringSSL would otherwise prompt for a passphrase on standard input.
- **HTTP behavior that NIO leaves to the application.**
  - **Parser errors.** An oversized request line or header fields get 431; NIO's default handler answers 400. Other parser errors get 400 and the connection is closed. llhttp's strict mode refuses `Content-Length` together with `Transfer-Encoding`, and repeated lengths.
  - **Body size.** Bodies over 256 KiB get 413. A declared oversized body is read and discarded, up to 1 MiB, so the client sees the answer; anything larger closes the connection.
  - **Expectations.** `Expect: 100-continue` is answered with 100 before the body is read (RFC 9110 §10.1.1). Any other expectation gets 417. Expectations in HTTP/1.0 requests are ignored.
  - **Methods and header fields.** Methods the API does not use get 405 with `Allow`. An HTTP/1.1 request without exactly one `Host` gets 400, as does a repeated `Authorization`, `Content-Type`, `Host`, `Expect` or `Lisa-Request-ID`.
  - **Request targets.** Percent-decoding is strict: `+` is not a space, `%2F` inside a segment is refused, and so are repeated query parameters. Clients encode targets with `APIRequest.encodedTarget()`, which uses only RFC 3986's unreserved characters.
  - **Timeouts.** NIO has none of its own. The first request head must arrive within 20 seconds of connecting, which also bounds the TLS handshake. A body must finish within 30 seconds of its head, and a kept-alive connection must start its next request within 30 seconds. Nothing is timed while the host prepares a response.
  - **Connections.** At most 64 at once; further ones are closed immediately.
  - **Response headers.** Every response carries `Cache-Control: no-store` and `X-Content-Type-Options: nosniff`. A 401 carries `WWW-Authenticate: Bearer realm="lisa"`.
- **Shutdown.**
  - The server stops accepting connections and sends each open one `ChannelShouldQuiesceEvent`, so requests in progress finish with `Connection: close`.
  - Connections still open after 5 seconds are closed. The runtime loop then stops and the data-directory lock is released.
  - `ServerQuiescingHelper` is not used, because it is in swift-nio-extras, which is not approved.
- **Resolved dependencies.**
  - `Package.resolved` gains swift-atomics 1.3.1, swift-collections 1.7.6, swift-nio 2.105.0, swift-nio-ssl 2.37.6 and swift-system 1.9.0.
  - swift-certificates, which swift-nio-ssl declares only for its own tests, is neither fetched nor pinned. The swift-crypto 5.1.1 conflict noted in the plan therefore does not arise.
- **The model request budget (MODEL-01).**
  - Every provider request, including the single repair attempt, is first reserved against `maxRequestsPerDay`.
  - The count is kept per owner-local day in `<data directory>/model-requests.json` (mode 0600), so a restart never resets it.
  - When the limit is reached, or the count cannot be read or written, items wait (MODEL-04). A damaged file, or one written by another version, is an error, never a reset.
  - The deterministic offline provider is not counted.

## D-45 — The companions' URLSession transport (API-01, NOTIFY-07)

- **Endpoint.** `HostEndpoint` accepts an `https` address, or `http` only for a loopback IP literal or `localhost`. It refuses user names and passwords, queries and fragments. An optional path prefix allows a reverse proxy that serves Lisa under a sub-path. Error messages never repeat the address.
- **Session.** `URLSessionTransport` uses one ephemeral session with no cookies, no credential storage and no cache.
  - Every request is a delegate-driven data task, so on every platform redirects are refused (a 3xx comes back as the response) and the 4 MiB response limit is enforced while the body arrives.
  - Requests that set framing headers (`Host`, `Content-Length` and similar), contain CR, LF or non-ASCII header values, or are GETs with a body are refused before sending. Paths must start with `/v1/` and are encoded with `APIRequest.encodedTarget()`.
- **Challenges.**
  - A challenge is never answered with a credential, except a server-trust challenge when a `ServerTrustEvaluator` is configured. The Security-framework evaluator that pins the host's key or certificate authority is an Apple adapter (Phase 8).
  - swift-corelibs-foundation never raises server-trust challenges, so on Linux the transport refuses to start with an evaluator rather than silently using system trust.
  - A 401 with `WWW-Authenticate: Bearer realm="lisa"` is safe on Linux: swift-corelibs-foundation raises a challenge only for Basic with a realm. Answering such a challenge with a credential would make it resend the request repeatedly, which the transport never does.
- **Failures on Linux.** swift-corelibs-foundation's error codes are not reliable: TLS failures arrive as `URLError -1`, and `cannotConnectToHost` can follow a request that was already delivered. The transport therefore reads libcurl's message.
  - A connect failure is `unreachable`, and a TLS handshake failure is `refused`.
  - Everything else is `interrupted`, so a queued mutation is retried with the same request ID and never assumed unapplied.
  - Reasons contain neither the message nor any request content.
- **Linux limitations.**
  - IPv6 literal hosts are refused when the transport is created, because swift-corelibs-foundation rejects every such URL.
  - `resourceTimeout` is ignored there.
  - FoundationNetworking's libcurl sends even loopback requests through a proxy named by `http_proxy`, `all_proxy` or `ALL_PROXY` unless `no_proxy` lists the host, and URLSession cannot turn that off. That is why the CLI reaches a running host with libcurl directly (D-44).
- **Not verified on Apple platforms.** The delegate method signatures, the server-trust path, `resourceTimeout`, IPv6 literals and system proxy behavior stay unverified until the apps are built and run on a Mac and devices (`NOT_RUN_ENVIRONMENT`).

## D-46 — Reading captured links (NEWS-01, SEC-02)

- **Path.** The application's `CapturedPageService` calls the `CapturedPageRetrieval` port in LisaPorts. LisaHost adapts `OwnerPageRetriever` to that port, using the connectors' libcurl client. The core never imports an adapter.
- **Who and what.**
  - Only the local owner and paired devices may ask; the model, runtime and demonstration principals get 403.
  - Only a `link` capture made by the owner is eligible. Ideas, text and Apple News shares are never fetched, and neither are links inside any content.
  - `OwnerPageRequest` checks eligibility again before any request is made.
- **Once per item.** `NewsItem.pageURL`, the final address after redirects, marks a page as read, so a second request is a 409 conflict. A read already in progress is a 503 with a 5-second retry.
- **Boundary.**
  - The new `ContentBoundary.pageText` labels what an anonymous reader sees, which for a paywall may be only the teaser. `fullText` would overclaim.
  - Text is bounded like a feed item's (4,000 characters, marked "…" when cut).
  - A page with a title but no readable text stays `titleOnly`. A title is replaced only when it was the bare link.
- **Provenance and retention.**
  - The item and its evidence are updated in one transaction: the evidence holds an excerpt and a reference to the raw page, which is stored as raw content kind `page` under raw-content retention.
  - If the transaction fails, the raw page is removed again. Deleting the item removes both.
  - Records are JSON bodies, so the new optional field needs no migration.
- **Failures.**
  - A lasting failure (sign-in or payment needed, not text, too large, refused address) is a 200 whose body says why, and leaves the item untouched.
  - A temporary failure is a 503 with the site's `Retry-After`, or 60 seconds. It is not recorded, so a retry with the same request ID runs again.
  - Each attempt is audited with its outcome and failure class only.
- **CLI.** `lisa capture --kind link --retrieve` derives the retrieval's request ID from `--request-id`, so a rerun replays. `--retrieve` with another kind is a usage error.

## D-47 — The Mac app's view models, model status in health, and current revisions in answers (UI-01, UI-03, MODEL-01, EVENT-01)

- **Where.** The Mac screens' view models are in LisaPresentation, beside the companion's, and are built and tested on Linux. The SwiftUI views come later and only display them.
  - Inbox: event proposals that need review, and extracted tasks still marked possible.
  - Ideas, and Memory (the owner's preferences).
  - Settings and health, which includes paired devices.
  - The brief screen can step through earlier days.
- **Model status in health.** `GET /v1/health` gains an optional `model` object, so the Mac app can show the model configuration in client mode too. It holds:
  - the provider (`none`, `deterministic` or `openAICompatible`), the model's name and where it runs;
  - `deterministic`, and `available`, which says whether the host could set the provider up (not that an endpoint answers);
  - the daily request limit.

  An OpenAI-compatible model is named by its configured identifier, never by the provider's descriptor, which contains the endpoint's origin. The object never holds an endpoint address, a key reference or a credential. Older JSON without it decodes as `nil`.
- **Answers carry the stored record.** Commands that change a task, idea, proposal, reminder or preference now answer with the record as stored after their follow-up work.
  - Before, when replanning changed the record again (as it does when it records why it cannot place an idea), the answer was one revision behind, so the client's next change conflicted.
  - A later runtime cycle, such as matching proposals against refreshed calendars, can still change a record after the answer. The next change then gets the recoverable 409.
- **Undated proposals.** A proposal with no date stays "needs details" even when the calendars hold nothing to compare it with. Before, matching against an empty calendar turned it into "not found".
- **Screen semantics.**
  - Dismissing an extracted task in the inbox cancels it.
  - "Schedule" for an idea offers it for planning; it becomes scheduled when the owner accepts the planner's block.
  - Idea changes are not in the offline queue. The Mac app reaches its host in process or on loopback, so an unreachable host is reported as unavailable and nothing is kept.
  - Two offline changes to the same preference or proposal are not merged: the second becomes a recoverable conflict.
- **Limits of the API, kept as they are.**
  - No route reads one idea or proposal, so after a conflict the screens look for it in the list, within a bound.
  - Tasks cannot be filtered by origin or confirmation, so the inbox filters open tasks itself.
  - No route lists preference keys: the app names the R1 keys itself and shows unknown keys by name.

## D-48 — The apps' shared Apple adapters (SEC-01, NOTIFY-05, NOTIFY-06, SIRI-01, UI-02, UI-03)

- **One process, one set of services.** `LisaClientEnvironment` holds the process's client, durable queue and response cache, and the app configures it once in `App.init`.
  - The App Intents live in the app targets, not in an extension. They run in the app's process and use the same queue, so each storage file has one writer.
  - An intent that runs before Lisa is set up reports that Lisa is unavailable.
- **Keychain.** These are generic-password items: the device's pairing identity, plus the embedded host's `keychain:` secrets on the Mac.
  - They are available after first unlock, on this device only, and are never synchronized.
  - On the Mac they use the data-protection keychain. That needs a signed build with a provisioning profile; otherwise it fails with `errSecMissingEntitlement`, with no fallback to the login keychain.
  - Service names derive from the bundle identifier: `<bundleID>.client-identity` and `<bundleID>.secrets.<service>`.
- **Files.** The queue, the cache and the connection settings live in `Application Support/<bundleID>/Client`.
  - The connection settings (the host address and any owner-supplied trust) are in `connection.json`, not UserDefaults.
  - The directory has mode 0700, is protected until first unlock on iOS and iPadOS, and is excluded from backups.
- **Host trust.** The owner can supply the host's certificate or its authority. `PinnedServerTrustEvaluator` then:
  - anchors only to that certificate, checks the host name and fetches nothing from the network;
  - can also pin the host certificate's SHA-256;
  - refuses anything else.

  Without owner-supplied trust, the system trust store and App Transport Security decide. Certificate validation can never be turned off.
- **Notifications.**
  - Categories and actions follow plan §6.5, with an explicit Open action and a hidden-preview placeholder per category. "Complete" needs the device unlocked.
  - A response goes to `NotificationActionHandler`: it is queued durably first, then submitted within 10 seconds.
  - Receipts are recorded only on paired devices, once per notification.
  - Authorization (alerts and sounds) is requested only when pairing offers it.
  - Push registration runs at each launch once the device is paired. The APNs environment follows the build configuration (`DEBUG`), matching the entitlements.
  - `Localizable.strings` holds every key the host sends, with generic text only.
- **Siri and Shortcuts (SIRI-01).** There are six intents. Tasks and reminders are entities keyed by the host's stable identifiers, and a spoken name with several matches asks which one is meant.
  - Replies are truthful: done, queued until Lisa is reachable, unavailable, or failed. A cached brief states its age.
  - Completing a task requires authentication.
  - Reading the brief or rundown, capturing, saving and snoozing can run while the device is locked, so an alarm automation can speak the brief (SIRI-02). The system's "Allow Siri When Locked" setting governs this.
  - "Read the brief" in the app speaks only while the app is in use. The brief and rundown intents return their text for Shortcuts to speak.
- **Evidence.** The pure logic is in LisaPresentation and is tested on Linux against a real in-process host: Siri replies, entity matching, token text, receipts and connection settings. The Apple adapters are only syntax-checked with `swiftc -parse`. Type-checking, Keychain entitlements, background time for actions, Siri timeouts and lock-screen behavior need an Apple build and devices.

## D-49 — The companion app (UI-02, UI-03, NOTIFY-05)

- **Layout.** iPad uses a sidebar with a detail view; iPhone uses five tabs, each with its own navigation stack. The screen in use is kept across iPad size changes. The app has one window, because the Info.plist has no scene manifest.
- **Launch and foreground.**
  - The shared environment is configured once, in `App.init`.
  - Each launch and each real return from the background reads the notification permission, reports it, sends the queue and refreshes the screen in use.
  - An APNs token is requested only once the device is paired.
  - Unpairing or a revoked credential hides every screen's data.
- **Notifications.** Opening a notification shows its screen, not the item itself, because no route reads a single task or reminder. An event proposal says to review it on the Mac, since UI-02 has no review screen. Permission is requested only from the pairing offer.
- **Known limits.**
  - Editing a task cannot remove an estimate, because the API has no way to express it. Setting or removing a deadline was added later (D-51), as were block actions and reading the rundown aloud.
  - The queue is sent on foreground return and on Send Now, with no network-change trigger.
  - Some display logic lives in the views and is untested on Linux: which screen a notification opens, words for states, and the changed-fields check. Moving it into LisaPresentation is follow-up work.
- **Evidence.** Syntax-checked with `swiftc -parse` on Linux only; not compiled for any Apple platform.

## D-50 — The Mac app outside the sandbox, and local-network transport security (APPLE-01, API-01, ARCH-03)

- **Not sandboxed.** The Mac app embeds the host. The host:
  - reads the owner's configuration and data directory at the same paths `lisa` uses, so the app, `lisa serve` and the CLI share one data directory under one lock (ARCH-03);
  - binds the API listeners and opens outbound connections through libcurl;
  - reads `file:` secrets from owner-only files;
  - writes the owner endpoint file in the data directory.

  A sandboxed app sees only its container and security-scoped bookmarks, so the app and the CLI could no longer share a data directory. The app uses the hardened runtime instead, with no entitlement that weakens it. Sandboxing becomes a separate decision if the app is ever distributed beyond the owner's own Macs.
- **`NSAllowsLocalNetworking`.** Both apps set it, and no other App Transport Security exception; in particular there is no `NSAllowsArbitraryLoads`.
  - It lets a device reach the host by a `.local` or unqualified name with the owner's own certificate.
  - It does not allow plain HTTP: Lisa's endpoint rules still require `https` except on loopback, and the host refuses plain HTTP off loopback.
  - The companion's trust rules (D-48) still apply.

## D-51 — The Mac app (UI-01, ARCH-03, NOTIFY-05, PLAN-04)

- **Layout.** One window with a sidebar: Today, Brief, Inbox, Ideas, Memory, and Settings and health. Menus and shortcuts cover the main actions: Command-N captures, Command-comma opens settings, Command-1 to 6 switch sections, and a Host menu holds the host commands.
- **Embedded host.** The app opens LisaHost in its own process, in mode `mac-app`.
  - It uses the CLI's configuration path (`$LISA_CONFIG`, otherwise `~/.config/lisa/config.json5`) and the CLI's secret stores, plus `KeychainSecretStore` for `keychain:` references.
  - It serves the network API and writes the owner endpoint file, as `lisa serve` does.
  - Quitting stops the server, removes the endpoint file, stops the runtime, and only then releases the lock. The app waits up to 20 seconds for this.
- **Client fallback.** When a running `lisa serve` holds the data directory, the app reads the owner endpoint file, checks the process ID as the CLI does, and connects through `LoopbackOwnerTransport`. It never switches mode by itself; Try Again switches at the owner's request.
- **Local notifications.**
  - With the embedded host, a notification is posted at delivery time with no trigger, identified by its delivery ID.
  - The transport reports one of three results: rejected, accepted, or confirmed delivered when Notification Center lists it.
  - Permission is requested only from "Turn On Notifications…".
  - The installation is registered through `LisaHost.registerLocalInstallation`, which reaches the host's store without an API route.
- **No notifications in client mode (owner decision, 2026-11-18).** While a running `lisa serve` holds the data directory, the Mac gets no Lisa notifications; the paired iPhone and iPad still get theirs.
  - Registering for APNs would need the Mac to pair as a device through the device listener, since the owner listener refuses push registration. It would then get every notification twice once it embeds the host again.
  - This replaces plan §6.5's statement that a Mac in client mode registers for APNs. Accordingly, the Mac app has no `com.apple.developer.aps-environment` entitlement, and only the companion's App ID needs Push Notifications (plan §6.9).
- **Start at login** uses `SMAppService.mainApp`, with its status and approval shown in Settings and health.
- **Keychain secrets.** Settings and health → Secrets stores values for `keychain:` references in a secure field. A stored value is never shown again.
- **Plan blocks.** On the Mac's Today and on the companion's rundown, blocks can be accepted, locked, rejected, deferred or completed. Actions go through the durable queue with the plan's revision, and conflicts are recoverable. The rundown can also be read aloud, stating its age when it is not current.
- **Gaps.**
  - Moving a block (PLAN-04) was added later (D-52).
  - A task's estimate cannot be removed, because the API has no way to express it.
  - Some display logic is in the views and is not tested on Linux.
- **Evidence.** Syntax-checked with `swiftc -parse` on Linux only; not compiled for any Apple platform.

## D-52 — Moving a plan block, and held parts of a task (PLAN-03, PLAN-04)

- **Moving.** The owner gives a block a new start and end on the same local day. The block becomes `locked` there, the only state the planner keeps exactly (D-15), and keeps its ID, subject and title. Its day is replanned around it in the same transaction, and its reminders follow it: the old one is cancelled and a new one is due 10 minutes before the new start.
- **What can be moved.** Proposed, accepted, locked, rejected and deferred blocks can be moved, on today's rundown or a later one in the owner's current zone.
  - A completed block is a 400.
  - A calendar event is a 403: it is changed in the calendar.
  - An unknown block is a 404; a stale revision is the usual 409.
- **Refused with 400, with the reason and the field.** Nothing changes when:
  - the end is not after the start, or a time is not a whole minute;
  - the block would leave the plan's local day (ending at the closing midnight is allowed);
  - it would overlap a busy calendar event (entries marked free don't count), or another accepted, locked or completed block.

  Planning windows, protected time and buffers shape Lisa's suggestions, but they do not limit where the owner puts a block.
- **Later changes.** Replanning keeps a moved block where the owner put it. If a new busy event later overlaps a moved or locked block, the block stays, and the plan warns that it now overlaps a calendar commitment.
- **Interfaces.** The API is `{action: "move", expectedRevision, start, end}`. `start` and `end` are left out of the JSON for other actions, so older clients are unaffected. The CLI is `lisa plan block move --block <id> --start HH:MM --end HH:MM [--date]`, in the rundown's zone; `24:00` is the closing midnight, and on a fall-back day a repeated time means its first occurrence. The Mac's Today and the companion's rundown offer "Move…".
- **Held parts of a task.** Before this change, a block the owner held (locked, moved, completed, or accepted and still valid) marked its whole task as placed. A splittable task's remaining minutes then vanished, neither planned nor reported. Now:
  - the remaining time is planned as further parts around the held one, with IDs that never repeat a held block's;
  - when the remaining time does not fit, it is reported as unscheduled with the minutes left;
  - a task that is not splittable stays as the owner placed it.

## D-53 — Dependency versions after the R1 freeze (R2 M0, run 20261124-r2-5462)

- **Permission.** The owner's start instruction of 2026-11-24 allows existing dependency versions to change after R1 is frozen, when necessary or beneficial: swift-crypto 5.1.2 first, an assessment of SwiftNIO 2.105.1, and any other change justified against the project's actual use (`DEVELOPMENT-ENVIRONMENT-REPORT.md` §13). P-08 (swift-certificates) is unchanged. The frozen R1 artifacts keep R1's own lockfile (SHA-256 `9608e8e0…a37494`), so this change never reaches them.
- **swift-crypto 5.1.1 → 5.1.2: adopted.**
  - Revision `f8fad2f95ad67b45f6340c0960e2396094d67e07` → `3280a5f72874d2f73bf25551bbb64f524c76d834`, the commit of the upstream 5.1.2 tag.
  - Why: 5.1.2 fixes GHSA-rch3-xxjq-365j (critical: X25519 key agreement accepted low-order public keys and returned the all-zero shared secret) and GHSA-c24m-vphm-p22w (medium: `KDF.Scrypt.deriveKey` did not enforce `maxMemory`). R1 calls neither, but the code is linked into every product that links `LisaCrypto`, and R2's `LisaCrypto` adds key agreement and HPKE helpers (plan §7.2.2).
  - Compatibility: the manifest change is a comment, so no requirement moves; swift-asn1 stays 1.7.4; P-08's candidate swift-certificates range `3.12.3..<6.0.0` still contains it.
  - Lockfile: only the swift-crypto pin and `originHash` change; SHA-256 `9608e8e0…a37494` → `f846319595094d9399eccd89f565e571db298f5dab8c46543bcd7d95bc91e776`. Commits `9e35866` (`Package.swift`) and `fd94a78` (`Package.resolved`, the buildable checkpoint).
  - Regression: the unmodified R1 suite passes 376 tests in 66 suites in debug and release with Swift 6.4.2 and 6.4.3, with 0 warnings, and the demo passes 30 of 30 (`docs/VERIFICATION-SCENARIOS.md`).
- **swift-nio 2.105.0 → 2.105.1: assessed, not adopted.** Its four changes: temporary directories created through `NIOFS` and `_NIOFileSystem` get owner-only permissions; the event loop's `autoreleasepool` is guarded by `canImport(ObjectiveC)`; a fix in `NIOTestUtils`' HTTP/1 test server; a CMake script. Lisa imports only `NIOCore`, `NIOHTTP1`, `NIOPosix` and `NIOSSL` and creates no temporary directory through `NIOFS`, so none of them changes Lisa's behavior. To be re-assessed if R2 adopts `NIOFS`.
- **swift-nio-ssl 2.37.6 → 2.37.7 and swift-asn1 1.7.4 → 1.7.5: not adopted.** The first only guards `Security.framework` use with `canImport(Security)` for Apple builds of `NIOSSL`, which no Lisa Apple target links; the second changes only CMake files.
- **Sources.** GitHub's public compare and security-advisory data for apple/swift-crypto, apple/swift-nio, apple/swift-nio-ssl and apple/swift-asn1, read without credentials on 2026-11-24.

## D-54 — The X1 proof app (R2 M1, run 20261124-r2-5462; plan §8.7, §8.9.3, §10.5 N-1 and E-1, §10.8)

`Apps/Proof` (scheme `LisaProof`) is proof-only: it never ships, no product links it, and it uses synthetic identities only. It was drafted, reviewed against HEAD and the plan, corrected, and checked on Linux (`swiftc -parse` on every file; the 38 files without an Apple-only import type-checked against HEAD's `LisaCrypto`, `LisaSyncProtocol`, `LisaTrust` and `LisaHTTP`; the certificate encoder's output verified with `openssl`). Nothing in it has been built or run on an Apple platform; that is X1's.

1. **Design B's TLS key is a Keychain-resident Secure Enclave `SecKey`** (`kSecAttrTokenIDSecureEnclave`, permanent), and the fixed-template encoder signs through `SecKeyCreateSignature`. §8.7 says the encoder signs "through CryptoKit", but Security forms a `SecIdentity` only from a Keychain item, which a CryptoKit Secure Enclave key is not. This is the protected-key path §8.7 names for X4, and X1's evidence stays what §8.7 states: Network framework mutual TLS with a Secure-Enclave-backed identity and roster pinning, not production issuance. The encoder file itself is Foundation-only and is the one the Linux check compiles with a software key.
2. **Design A's listener registers its PSK identities in advance.** Network framework's PSK selection block is a client-side choice among identities already added, so the listener can't compute a key per handshake as §8.7 words it. It adds, for each active roster peer (at most 9), that peer's discovery tag and rejoin identity for the windows w−1, w and w+1, each with K_ij (at most 54 entries), and is recreated at every 15-minute boundary. The identities and keys are exactly §8.7's; only when they are computed changes. An optional probe records whether the block is ever called on the listener.
3. **Rejoin trials.** A TLS 1.2 client offers one PSK identity per connection, so a rejoining device tries one candidate peer per connection on each service found: at most 9 services × 9 candidates, sequentially, under the per-endpoint backoff.
4. **Result records add three fields.** `OV-NEAR-<pair>-<NN>` serves both designs' proofs (§10.9), so each record carries `design` (A or B), `pairSession` (base case, role, devices, condition, the harness nonce, the session codes shown) and `checks` (the N-1 criteria, one ID each: peer identification, unenrolled identity refused, exporter-bound hello, wrong binding refused, reconnection after kill and after the Wi-Fi toggle, deduplication, 100 frames timed, TLS version and suite recorded, the local-network prompt and denial, and for Design A the forward-secret ECDHE-PSK suite). The harness result schema (`Harness/docs/RESULTS.md`) includes them.
5. **Fetch probe case IDs.** `OV-APPLE-X1-FETCH-01`–`09` follow §8.9.3's nine probe items in order: public https URL; private-only name refused; mixed name; system proxy unused; IPv6-only NAT64; dual-stack; independently translated destination; split-tunnel VPN; platform behavior. E-1's literal and redirect cases are subcases of 01 (public IPv4 literal), 02 (private, mapped and `64:ff9b::` private literals, redirect to a private address), 05 (a `64:ff9b::` literal of a public address on the NAT64 network) and 06 (a global IPv6 literal and a redirect to one, both deferred).
6. **Run IDs** are `run-YYYYMMDDTHHMMSSZ-<6 characters of lowercase RFC 4648 base32>`, generated by `lisa-verify`; the app checks the shape.
7. **The local-use prefix `64:ff9b:1::/48`** (RFC 8215) has no fixed embedding length, so the probe defers a literal under it unless a discovered prefix contains it. M7's portable destination policy decides this for production.
8. **E-2 case order:** `OV-APPLE-X1-01` Mac, `-02` iPhone, `-03` iPad, as §10.9 lists them. The build-log digest comes from the owner's Xcode build through `lisa-verify`, not from the app.
9. **The local-network prompt and denial** are recorded per device and installation (the prompt belongs to the app's installation) and copied into each cell record of that device.
10. **Assumptions X1 observes and records,** none of which the app relies on silently: an accepted connection survives the listener's replacement; the TLS 1.2 PSK exporter is available; `tls_ciphersuite_t(rawValue:)` keeps unlisted values (the negotiated suite is checked against the offered list either way); the `dnssd` module name; XcodeGen's `supportedDestinations`.
11. **Portable contracts adopted now:** `NearbyFrameHeader` (LisaSyncProtocol: total length, kind, version 1, reserved bytes, the 1 MiB budget checked from the header) and the hello's canonical JSON form (LisaTrust), which the proof uses, so X1 exercises them on the devices. **Kept as labeled proof stand-ins:** an agreement boundary for Secure Enclave agreement keys (with `Apps/Shared/Keychain`, M5/M6; the proof keeps a software agreement key in the Keychain and records the operation key's storage), the NAT64 prefixes and destination policy (M7, S-14), and session deduplication, per-endpoint backoff and the discovery-secret handover (M6).
12. **Design B's unenrolled-identity case presents a second, throwaway Secure Enclave identity** that no roster lists, so the refusal happens in the peer's verify block during the handshake, which is what roster pinning has to show. (The draft refused it only at the session layer.)
13. **The Mac proof runs in the App Sandbox** (network client and server, its keychain access group), unlike R1's unsandboxed Mac app (D-50), so X1 also observes `SecIdentity` formation and listening under the sandbox; E-10 remains X3's and X7's.
14. **Not in the proof, and not needed for N-1, E-1 or E-2:** the 250 ms dial stagger and the restart on a path change (production retrieval, M7, X5); QR scanning (cards and the setup text are copied as text); the inventory and exchange phases (M6); removal of the Secure Enclave TLS keys and certificates by the app's reset.

## D-55 — SQLite's WAL-reset bug: one writer and checkpointer per database (R2 M2, run 20261124-r2-5462; plan §1.5, §8.15.2; `DEVELOPMENT-ENVIRONMENT-REPORT.md` §13)

- **The condition.** SQLite's WAL-reset bug, fixed upstream in 3.51.3, needs two connections writing or checkpointing the same WAL database at the same instant (plan §1.5).
- **The loaded library isn't shown to be fixed.** This host loads `libsqlite3-0` 3.46.1-7+deb13u2+dhi4, the Docker Hardened Images rebuild of Debian's 3.46.1-7+deb13u2, which carries no changelog.
  - Debian's own packaging for 3.46.1-7+deb13u2 was fetched from deb.debian.org on 2026-11-24; its SHA-256 `59d33bc4…c21261` matches the `.dsc`.
  - Its changelog and 15-patch series contain no WAL fix: packaging and build patches, the NOT NULL/IS NULL optimization fix, and CVE-2025-29087, CVE-2025-29088, CVE-2025-6965, CVE-2025-7709, CVE-2026-11822 and CVE-2026-11824 (FTS5, aggregates, `db_config`).
  - What the `+dhi4` rebuild adds isn't published here.
  - The production image's library is inventoried at M4 and judged the same way.
- **So the design excludes the condition** for every database R2 opens in WAL mode (the replica store, the Core ledger, the recovery ledger and their auxiliaries):
  1. one process at a time, under the data directory's exclusive lock (plan §8.5.1, §8.11.5);
  2. inside it, exactly one read-write connection, which performs every write, the automatic checkpoint that follows its own commits, and every explicit checkpoint;
  3. every other connection opened read-only (`SQLITE_OPEN_READONLY`), so it neither writes nor checkpoints, not even on close;
  4. offline commands (backup, restore, fence, migrate) take the same exclusive lock with the service stopped, so they are never a second writer.
- **Verification.** M2's `LisaSQLite` additions give each connection a declared role. The temporary harness (S-17) shows that a second read-write open of a held database is refused, a read-only connection neither writes nor checkpoints (the WAL is unchanged by its reads and its close), and checkpoints run only on the writer. M2 and M3 durability results are accepted only with these checks passing. If a later library carries the fix (3.51.3 or a verified backport), the rule stays: it costs nothing and removes the dependency on the library's version.

## D-56 — LisaReplicaStore uses LisaTrust and LisaCrypto directly (R2 M2, run 20261124-r2-5462; plan §7.2.1, §8.2.1, §8.6.1)

- **The plan's table** lists LisaReplicaStore's direct dependencies as LisaSQLite, LisaDomain, LisaMerge, LisaSyncProtocol and LisaArchive. LisaArchive already depends on LisaTrust and LisaCrypto, so the graph doesn't change; only the edge becomes direct.
- **Why the store needs them.** The duplicate rules hold on every replica with no exception (R2-SYNC-02).
  - So the store computes each operation's digest itself: SHA-256 over the exact signed body, LisaTrust's `OperationDigest`. It does this for the operations it creates and for those that arrive.
  - Before applying an arriving operation, it verifies the dataset, the origin key and the signature with `OperationSigning.verify` (R2-L16). The roster's keys reach it as LisaCrypto's `P256Verifier`.
  - A port for these would only re-wrap LisaTrust.
- **What stays as planned:**
  - Signing stays behind the `ReplicaSigning` port: a Keychain or Secure Enclave key on Apple devices, `SoftwareReplicaSigner` in harnesses.
  - LisaMerge, LisaDomain and LisaArchive join when the effective view, the record projections and export assembly use them.
  - No module outside the plan's set is added, and the graph stays acyclic: LisaTrust and LisaCrypto depend on neither the store nor anything that uses it.

## D-57 — LisaLocalSearch uses LisaSyncProtocol directly (R2 M2, run 20261124-r2-5462; plan §7.2.1, §8.6.1)

- **The plan's table** lists LisaLocalSearch's direct dependencies as LisaSQLite, LisaDomain and LisaReplicaStore.
- **Why it needs LisaSyncProtocol.** The index names items by `ReplicaItemKey`, whose ID is LisaSyncProtocol's `Identifier128`, so the module imports LisaSyncProtocol directly. LisaSyncProtocol is already in the graph through LisaReplicaStore.
- **What it reads, and where its table lives:**
  - It reads an item's searchable text through `ReplicaStore.searchableText(of:in:)`, inside the change's transaction, so it needs no LisaMerge.
  - Its postings table belongs to the replica schema, so the store can swap a staged index with the rest of an installation (plan §8.6.3).
  - LisaDomain joins when other item types are indexed.

## D-58 — R2 entity IDs are R1 record IDs spelled as UUIDs (R2 M3, run 20261124-r2-5462; plan §8.4.1, R2-MIG-01)

- **The question:** the plan leaves the mapping unstated. An R2 operation names its entity by a 128-bit `Identifier128`, while R1 names a record by a string. R1's own IDs are lowercase UUIDs (`EntityID.random()`), and Core projects every entity into R1's records.
- **The decision:** the record of entity `e` has the ID that spells `e`'s 128 bits as a lowercase UUID, `8-4-4-4-12` (`R1Identity.uuidString`). Reading an R1 UUID back gives the same 128 bits (`R1Identity.entityID(fromUUID:)`).
- **Why:**
  - The mapping is exact in both directions for every ID R1 generated, so R1's IDs survive migration unchanged (R2-MIG-01).
  - R1's API, planner and reminders keep reading the records they know.
  - No mapping table is needed for items created under R2.
- **Not covered:** an R1 record whose ID isn't a UUID. If migration (M9) finds one, it gets a stored mapping then.

## D-59 — LisaCoreLedger's dependencies, and R1's store opening one transaction for the ledger (R2 M3, run 20261124-r2-5462; plan §7.2.1, §8.4.1)

- **The plan's table** lists LisaCoreLedger's direct dependencies as LisaStore, LisaPorts, LisaMerge, LisaTrust, LisaSyncProtocol, LisaFiringIdentity and LisaLogging.
- **What it also uses directly:**
  - LisaSQLite, for its own tables and the savepoint per operation;
  - LisaCrypto, for the resolution-group digest;
  - LisaDomain and LisaTime, for R1's `LisaTask` and `Deadline` in the projection.
  - LisaFiringIdentity and LisaLogging join when holds and logging arrive (M3-8).
- **One transaction for ledger and records:** intake must commit an operation's ledger rows and its projection into R1's records together (plan §8.4.1). R1's `RecordSession` is internal, so `SQLiteRecordStore` gains `ledgerWrite` and `ledgerRead`, which hand the body both the transaction's `SQLiteSession` and R1's record writer. This is a change to R1's non-test code. R1's tests are untouched and pass.
- **Schema v5:** R1's migration list gains version 5, the ledger tables. Every table keeps its rowid, because R1's migration tests snapshot every table in rowid order. Two `WITHOUT ROWID` tables broke them at first and were changed before any commit.
- **Shared rules, two copies for now:**
  - Core's persisted causal release and its task fold, with paged resolution groups, follow the replica's rules in Core's own tables and code.
  - The plan keeps Core and client modules apart: Core never links LisaReplicaStore. Moving the shared parts into LisaMerge is a later refactor, which would carry the replica's regressions with it.

## D-60 — The v2 sync routes join R1's server through one defaulted hook; the shared transport reaches `/v2/` (R2 M3, run 20261124-r2-5462; plan §8.6.5, §8.12.1)

- **Server:**
  - `HostAPIServer.start(for:limits:v2:)` gains a defaulted `v2` handler, tried first for requests on the devices listener. It answers `nil` for paths it doesn't own, and R1's router then answers them as before.
  - Without the handler nothing changes: `lisa serve`, the owner listener and R1's in-process router, which still answers `/v2/` with R1's typed 404 (`L20APIValidationTests`).
  - The composition root passes `CoreAPIRouter.handle`.
- **Client:** LisaClient's `HostEndpoint.url(for:)` accepts `/v2/` paths as well as `/v1/`, as the plan's shared transport requires (§8.6.5). No R1 test checks the old refusal, and R1's own callers only send `/v1/`.
- **Body limit:** the server's request limit stays R1's 256 KiB for every path, because one R1 test depends on its close-on-413 behaviour. A per-path limit for `POST /v2/operations` (512 KiB in the plan) waits for a change to LisaAPIServer's request assembler that keeps that behaviour for `/v1/`.
- **Dependencies:**
  - LisaCoreAPI uses LisaAPIContract, LisaCoreLedger, LisaSyncProtocol and LisaCrypto (the roster's keys). LisaApplication, LisaDevices and LisaPorts join with enrollment and the other v2 routes.
  - LisaSyncEngine uses LisaSyncProtocol, LisaTrust, LisaReplicaStore and LisaCrypto.
  - LisaSyncHTTP uses LisaSyncEngine, LisaClient, LisaAPIContract and LisaSyncProtocol.
- **Credentials and keys:** device authentication is R1's bearer credential, through `LisaApplication.authenticateDevice`. The roster that gives each device's operation key is a resolver the composition root provides, until enrollment and the roster arrive (M3-5).

## D-61 — A replica may release its ballast to open when storage is full (R2 M3, run 20261124-r2-5462; the owner's decision of 2026-11-25; plan §8.15.2 amended)

- **Override:** plan §8.15.2 releases the storage ballast only on the capture path. On 2026-11-25 the owner allowed releasing it to open the replica at launch, provided every report states the override, the file affected and the recovery.
- **Why:** M2-4 found that at 0 bytes free the replica couldn't be opened. Opening records the launch's incarnation, and WAL mode needs room for its `-wal` and `-shm` files. Every saved capture stayed intact, but the app couldn't reach its own data until space returned.
- **Mechanism:** `ReplicaStore`'s initializer counts an open as failed for lack of space in two cases: SQLite reports `SQLITE_FULL`, or it reports an I/O error (on a full tmpfs it can't create its sidecars) while the file system has less than one capture reserve left. Then:
  - it empties the ballast file (`reserve.bin` in the replica directory, truncated to 0 bytes; the file stays) and opens once more;
  - `releasedBallastAtOpen` and `storageIsAlmostFull` say so, and the app shows "Storage is almost full";
  - with the ballast already empty, or if the second open also lacks space, the error is `storageFull`, never a misleading I/O error.
- **Recovery:** the ballast is restored whole by `restoreBallastIfSpaceReturned()` once a full reserve would still be free after it, or at a later launch when space has returned. Nothing else is deleted, and the database, WAL and saved work are untouched.
- **Evidence:** `docs/VERIFICATION-SCENARIOS.md` M3-D61, a real full tmpfs in the pinned container.

## D-62 — Core keeps its own device registry for R2 enrollment; the trust formats and their bindings (R2 M3, run 20261124-r2-5462; plan §8.1.2, §8.1.3, §8.12.1)

- **Registry:**
  - R2 devices enroll into Core's own tables (schema v6: `core_enrollments`, `core_devices`, `core_rosters`, `core_revocations`, `core_credential_resets`, `core_challenges`, `core_trust_events`), not into R1's pairing registry.
  - A router made from `CoreTrust` authenticates v2 requests by Core's registry: the bearer credential's SHA-256 must match an active device's verifier. It takes operation keys from the same registry.
  - R1's pairing and its v1 credentials are unchanged. The legacy link that connects an R1 companion to its R2 enrollment is §8.14.5's (M3-6 and later), and is not yet part of the request.
- **Request digest:** SHA-256 of the exact signed request body, the bytes the device's signature covers, as for operations (§8.2.1). A retry replays the identical body and signature.
- **Anchors bundle:** it carries no time, so its body, and therefore the digest the roster carries, depends only on the dataset and the configured CA and intermediates, and stays the same across Core restarts. Freshness comes from the roster that binds the digest.
- **Roster pages:** the summary first, then devices (64 a page), then revocations (256 a page), each a canonical object. The summary's counts fix how many pages of each kind there are, on top of the header's page count and Merkle root.
- **The newest roster must verify under the current signer.** Otherwise, as after a restart under another key, Core signs a new version at once. Signing-key rotation proper (dual-signed transitions and key history, §8.1.4) is a later M3-5 slice.
- **Revoked origins:** operations from a revoked device are refused before anything is stored (`unverified`, because the registry gives no key), whoever submits them and whatever time they claim. Committed data stays.
- **Device-side trust lives in the replica:** `trust_state` and `trust_rosters`, added to the unreleased replica schema v1 in place. The pending item, which holds the secret-bearing request, is a port (`PendingEnrollmentStore`): the Keychain on Apple platforms, a file-backed stand-in in the harnesses.
- **The owner's intended name and class** from issuance go into the roster. The request's class must match the intended one; the device's own name is informational.

## D-63 — Capabilities negotiation: Core's features and `upgrade_required` (R2 M3, run 20261124-r2-5462; plan §8.12.1)

- **Capabilities** gain `features`, strictly ascending tokens for what this Core offers: `challenges`, `changes`, `credential-reset`, `enrollment`, `operations`, `receipts`, `trust`. Later spans add theirs.
- **Version:** a request whose `Lisa-API-Version` names another major version gets 426 `upgrade_required`, before any route runs (an enrollment included, so no attempt is counted). Another minor version is answered.
- **A request without the header** is taken as 2.x, so the clients and harnesses written before this decision keep working. Every Lisa v2 client sends the header.
- **Required capabilities:** a client names them in `Lisa-Required-Features`, comma-separated; any Core lacks gets 426 `upgrade_required`.
- **The client side:** `CoreSession` refuses a Core whose capabilities name another major version, before it touches the replica.
- **Still to come:** the other capabilities fields the plan lists (schema version, the head's confirmation, trust and policy versions, the backup catalogue, the recovery stage, the ready-queue length and redacted health) arrive with the spans that own them.

## D-64 — The per-path body limit: `APIServerLimits.bodyLimitsByPath` (R2 M3, run 20261124-r2-5462; plan §8.12.1; closes D-60's open point)

- **Server:** R1's `APIServerLimits` gains `bodyLimitsByPath`, exact request paths mapped to their own body limit, and empty by default. The request assembler takes the path's limit when one is configured, and otherwise `maxBodyBytes`.
- **Behaviour:** exceeding either limit gets the same 413, drain and close R1 tests for. Without the map, R1's behaviour is byte-for-byte what it was.
- **Core:** `CoreAPIRouter.bodyLimits` maps `/v2/operations` to 512 KiB, the plan's budget for one submission, and the composition root passes it. Every other path, v1 or v2, keeps 256 KiB.
- **Matching:** paths match exactly, before the query, so a prefix can't widen a limit by accident.

## D-65 — Signing-key rotation: the transition, the key history and which key verifies which record (R2 M3, run 20261124-r2-5462; plan §8.1.1, §8.1.4, §8.5.3)

- **The transition** (`SigningKeyTransition`): `{datasetID, sequence, previousKey, nextKey, activationPosition, issuedAt}`, signed by both keys over the same body under `lisa-r2-key-transition-v1\n`. The activation position is Core's last commit position plus one at the rotation, so the previous key signed every position before it and the next key signs every position from it.
  - A rotation with nothing committed since the last one is refused, so every key signs at least one position.
- **Core:**
  - Schema v7's `core_signing_keys` holds the anchor (sequence 0) and each transition.
  - The ledger that rotates retires its signer at once and signs nothing more. Core restarts with the next key's private half.
  - Opening requires the signer to be the history's current key: a retired key gets `signerRetired` and an unknown key `signerMismatch`. So Core never signs with a retired key and never forks the history.
- **On a fresh host:** a store restored from after the rotation opens with the restored current key.
  - **An older store:** `CoreLedger.importKeyTransition` (`lisa core trust import-key`) appends a transition that continues its history, and only once the store has reached the activation position.
  - **Backups behind the activation:** a backup older than that, with the epochs a restore starts, is M3-7's.
- **Which key verifies which record:**
  - **A final receipt** by the key valid at its commit position, so a retired key verifies only receipts from before its retirement.
  - **Artifacts signed when served** (change pages, snapshots, rosters, anchors bundles, enrollment results) by the current key. They carry no signing position, and a retired key never signs them.
  - **A provisional receipt** by any key of the history: it has no position and never counts as commitment. One issued before a rotation may come back unchanged on a retry.
- **Distribution:**
  - `GET /v2/trust` answers `{"roster", "keyTransitions"}` once Core has rotated.
  - `CoreSession(replica:transport:)` takes the transitions and the roster first in each reconciliation (§8.6.5 step 2). It verifies the chain before trusting the roster under the new current key.
  - **Anchors and sequences:** sequences are Core's. A device anchored by an owner text issued after a rotation learns its anchor's sequence from the transition that activated it, and skips what came before.
- **The harness's earlier signer change:** M3 harness v10 (and the harnesses that carried its tests) reopened Core with a new key and no transition, and that is now refused by design. Harness v20 rotates first.
- **Later:** appending the transition to the recovery ledger and backup sets, and anchoring from an independent key backup, come with M3-7, and re-anchoring with S-10.

## D-66 — Device key rotation, and historical keys for committed operations (R2 M3, run 20261124-r2-5462; plan §8.1.3, §8.1.4)

- **The update** (`DeviceKeyUpdate`): `{datasetID, deviceID, previousKey, nextKey, createdAt}`, signed by both keys under `lisa-r2-device-key-update-v1\n`, in the two-signature form of Core's key transitions. It is sent to `POST /v2/devices/current/key-update` under the device's own credential.
- **Core,** in one write transaction:
  - **It requires** both signatures, the authenticated device and the dataset, the registry's current key as `previousKey`, a `nextKey` no device holds or held, and no operation of the device waiting for dependencies. A waiting operation would commit after the change under the old key, which no replica could then verify by the roster's current key.
  - **It then** keeps the previous key in `core_device_keys` (schema v8) with the position from which the next key took over, makes the next key current, and signs a new roster whose device entry lists `previousKeys`.
  - **New operations** from the device verify only with the next key.
- **The device:**
  - It accepts the roster.
  - It re-signs its own pending and submitted operations with the next key (`ReplicaStore.resignLocalOperations`). The digest leaves out the signature, so their IDs and digests don't change, and a copy a peer holds under the old key is a duplicate of the re-signed one.
  - Its signing port switches to the next key.
- **Committed history:** replicas verify the operations in Core's signed pages, repairs and snapshots with the device's current key or, through a defaulted `previousKeys` resolver, the keys it rotated away from. Core's page signature vouches that it committed them.
- **A defect found while designing this:** the same resolver gives a revoked device's last key for its committed operations. Before, the roster's resolver gave a revoked device no key, so a replica pulling pages that carried that device's operations committed before its revocation would have refused them. "Committed data stays" (§8.1.3) now holds on replicas too. Peers' uncommitted operations still verify only with the current key.

## D-67 — Legacy children's origin and derivations, and the conversion frame (R2 M3, run 20261124-r2-5462; plan §8.12.2)

- **The origin:** `OperationOrigin.coreLegacyTranslation` now carries the incarnation derived from the request (`lisa-v1-incarnation-v1`) and the child's index plus one as its sequence, as §8.12.2 fixes them. M1 had left the case without values.
  - **Unreleased:** the envelope format is unreleased.
  - **M1's harness v2,** which built the old case, is kept as it was and no longer builds against the working tree. It is M1's evidence and isn't in the regression packages.
- **The scheme's constants:** schema and policy versions 1 for every child; no creation time; no observed set.
- **Created entities:** an entity a request creates gets the child-ID derivation of `entity:<discriminator>`, so its ID, and through R1Identity its R1 UUID, is fixed by the request.
- **Chains:** the caller names each change's chain (an entity, or a preference key), and a child depends only on its immediate predecessor in that chain.
- **The frame:** `CoreLedger.legacyConvert` runs one write transaction.
  - **Inside it:** the parent's lookup again, the route's conversion (which takes Core-signed children through the ledger's own intake, `LegacyTransaction.intake`, inside the same transaction, and reads R1's records there), and the parent's record.
  - **Kept or not:** an answer R1 wouldn't record, or a failure, commits nothing.
  - **Route semantics** stay in LisaLegacyRequests (M3-6a's next step), so the ledger knows no R1 route.

## D-68 — One R1 revision step per R1 call: the deferred projection and the projection-revision map (R2 M3, run 20261124-r2-5462; plan §8.12.2 "Projection revisions", §8.3.2)

- **Why:** R1 raises a task's revision once per service call: one for a correction, however many fields it names (even none changed), and one for a status change. R2 projected each applied child into R1's record, so a correction of two fields would have raised the revision twice.
- **The deferred projection:**
  - `LegacyTransaction.intake(_:projecting: false)` takes a request's field children in without projecting.
  - `project(_:forceRevision:)` then writes the entity once, as R1's `TaskService.correct` does, forcing the write when nothing changed.
  - A status child projects itself.
  - `TaskProjection.project(force:)` is the same projection with that one exception.
- **The projection-revision map** (schema v10, `core_projection_revisions`): every write into R1's record records which commit position its R1 revision reflects, so a v1 edit "observed at projection revision N" (§8.3.2) can be mapped to the pieces it saw. `CoreLedger.projectionPosition(of:revision:)` reads it.
- **Found while building this** (M3 harnesses v28 and v29):
  - **The gap:** legacy edits without an observed set are `accepted_with_conflict`, concurrent with the values they replace. The merged title then shows both candidates, and the display-order first, the old title, wins.
  - **The fix:** the "observed at projection revision N" rule. The child's body carries N, Core maps it to a horizon at that revision's position, and the result must reach replicas in Core-signed data (they don't hold the map). It is M3-6a's next step, to settle after reading §8.3.2's rule in full.

## D-69 — "Observed at projection revision N" resolved by Core when it decides the child (R2 M3, run 20261124-r2-5462; plan §8.3.2, §8.12.2; follows D-68)

- **The body** carries R1's `expectedRevision` as the observed set's `projectionRevision` (`ObservedSet`, `LegacyChange.observedRevision`). It stands alone, so the body stays a pure function of the request, and a device's operation may not carry it.
- **The resolution** happens when Core decides the child, in the deciding epoch:
  - Core reads `(epoch, P(N))` for the entity's revision N from the projection-revision map, which records each revision's epoch from schema v11 on.
  - It keeps the horizon `(epoch, "tasks", P(N))` with the operation (`core_operations.observed_epoch` and `observed_position`, set together).
  - Core's fold uses it in place of the envelope's observed set (`CoreOperationRecords.resolveObservedRevision`, `CoreTaskFold.view`).
  - Stored, not recomputed: another epoch may resolve the same bytes differently (§8.12.2, "Decisions are made per epoch").
- **Exactly P(N), not everything committed:**
  - **The rule:** the child supersedes the pieces R1's revision N reflected and nothing later.
  - **In R1's flow:** R1's revision check admits only N equal to the current revision, so the edit replaces what the caller read.
  - **Beside it:** a piece committed after P(N) without changing the record, for example a device's same-value edit, stays beside the child, as §8.3.2 keeps "a later arrival".
  - **The harness** (M3 harness v33) shows it with a stale revision: the newer title stays.
- **A revision the map doesn't hold** resolves to nothing. The child observes nothing and conflicts rather than superseding pieces it may not have seen. Records whose revisions predate Core, such as R1 data at cutover, need their mapping recorded when they are imported (M3-6d and M5, open).
- **Replicas (done 2026-11-26, M3-6a):**
  - **Why Core serves it:** replicas don't hold the map.
  - **What Core sends:** the resolved horizon, in its signed data. `ChangeEntry.observedHorizon` appears on a committed legacy child's entry only, in change pages and snapshot chunks (`53e2a5a`–`ccce9e1`).
  - **What a replica does:** it keeps the horizon with the canonical operation (`canonical_operations.observed_*`, staged through installations) and folds with it as Core does (`6e84d1b`–`89fcb1a`).
  - **Evidence:** M3 harness v34 shows the same views at Core and on a replica, by pages, by a snapshot, and by pages after a snapshot.

## D-70 — Apple app code is type-checked on Linux against framework stand-ins before each owner build (R2, run 20261124-r2-5462; after X1 attempt 1; plan §10.6, §17 "Scale")

- **Why:**
  - X1's first Xcode build failed at `Apps/Proof/Nearby/ProofNearbyController.swift:130`: "failed to produce diagnostic for expression".
  - M1-8 had type-checked only the 38 proof files without an Apple-only import. The other 31 had syntax checks only.
  - The failure isn't Apple-specific. Swift 6.4.2 and 6.4.3 on Linux reproduce it exactly, from a minimal copy and in the whole target.
- **The practice:** before an owner session builds Apple code, the whole target is type-checked on Linux as one module.
  - **Setup:** Swift 6 mode, with the real portable modules built from HEAD and the real Observation module.
  - **Stand-ins:** for the Apple frameworks it imports, carrying the SDK's Swift signatures and the Sendable and isolation annotations as known.
  - **Passes:** one per platform condition (`canImport(UIKit)`, `os(macOS)`).
  - **A baseline:** a pass with the last failing source, to show the check catches what the owner saw.
  - **Negative controls:** to show it reaches view-builder bodies, handlers and Swift 6 isolation checks.

  The stand-ins and runs stay in the run directory. `docs/VERIFICATION-SCENARIOS.md` records each run.
- **Its limit:** a stand-in is only as right as its signatures. An Apple build stays the owner's evidence (C5). Where an SDK annotation is uncertain, the app code is written so that it compiles either way.
- **First use, X1 attempt 2:**
  - **Line 130:** an untyped closure as a branch of `? :` isn't inferred `@Sendable` from the declared type. With `[weak self]`, the compiler fails to report the conversion error. The fix writes the closure explicitly `@Sendable` and assigns it in an `if` (`f03cf24`).
  - **Uncertain annotation:** whether `Binding(get:set:)`'s closures are `@Sendable` in the iOS 18 SDK. The proof views now bind through key-path subscripts on `ProofModel` (`0528fc3`–`795b4f3`).
- **Next uses:** X2's probe app (after M3) and the production apps before X3 (M5), the same way.

## D-71 — R1's task routes through the one legacy converter: the router hook, the module wiring, and notes at creation (R2 M3, run 20261124-r2-5462; plan §8.12.2, §7.2.1)

- **Where the semantics live:** `LisaLegacyRequests.LegacyTaskRoutes`.
  - **What it holds:** each converted route's R1 semantics: R1's checks in R1's order with R1's errors, the children, one projection, and R1's audit event. Queue imports (§8.14.4) can later use the same converter. LisaCoreLedger keeps the frame (`legacyConvert`).
  - **Module wiring:**
    - LisaLegacyRequests now depends on LisaCoreLedger, LisaDomain, LisaOwnerData, LisaPorts and LisaTime.
    - R1's `TaskService` rules are public and unchanged.
    - LisaAPI depends on LisaCoreLedger and LisaLegacyRequests.
    - All of these are Core-only.
- **The router hook:** `RouterConfiguration.legacyConverter` is nil by default, and `APIRouter.converting(with:)` returns the same router with a converter. With one, a converted route (so far `POST /v1/tasks`) goes through `converted`:
  1. **R1's own ledger first:** a key that a not-yet-converted route recorded keeps R1's answer.
  2. **Then `legacyConvert`:** its closure runs R1's body checks inside the parent, so 400 and 413 answers replay (D-35), then R1's checks, then the children. R1's DTO rendering stays in LisaAPI and runs inside the transaction.
  3. **The other routes check the parents too,** so each caller keeps one key space across both stores (R1's 422).
- **Not yet enabled in LisaHost:** R1's host composes R1's router unchanged until every v1 mutation route is converted (M3-6b–e). Mixed mode is safe, but it is a transition state.
- **Notes at creation:** R2's `task.create` payload has no notes, and §8.12.2's table lists only `create:task`.
  - A v1 create with notes therefore adds a `field:notes` child (`note.add`) after `create:task`, chained to it.
  - Both are taken in without projecting, then projected once, so R1's record is created at revision 1 with its notes, as R1 creates it.
- **After the commit:** R1's domain changes (planning, reminders) are propagated after the conversion commits.
  - A failure there is logged, and the answer stands. The host's cycle replans and syncs reminders.
  - A durable follow-up record is later work.
- **Terminal replies for `POST /v1/tasks`,** built from current state when the body has expired:
  - 409 "This task was created earlier; its reply is no longer available.";
  - or 404 "The task this request created was deleted afterwards.".

  The `lisaCode` field comes with M3-6d.
- **A concurrent duplicate** waits for the first conversion's transaction and then replays it, where R1 answers 503 "the same request is still being processed". The parent lookup inside the write transaction prevents a second conversion.
- **Shown by M3 harness v36** (v35 failed to compile and is kept). The same requests on R1's router and on the converting router give:
  - the same 201 `TaskDTO` but for the derived ID;
  - the same audit event;
  - the same replays, 422 and recorded 400s.

  The children are Core-signed and replicate. Keys are shared with unconverted routes, and a device creates under its own scope.

## D-72 — R1's `PATCH /v1/tasks/{id}` through the converter: field children, the status, R1-only states, and two protocol rules (R2 M3, run 20261124-r2-5462; plan §8.12.2, §8.2.3, §8.3.1–§8.3.2)

- **The conversion** (`LegacyTaskRoutes.update`, `convertUpdateTask`) runs inside the parent, in R1's order:
  1. the body size (413);
  2. its decoding (400);
  3. the record (404 "the task");
  4. the revision check (409 "the task changed since it was read", with `currentRevision`);
  5. the correction, its deadline parsed (400);
  6. `TaskService.correct`'s checks: the principal (403), the minutes (400), the title (400).

  Nothing is committed before these checks, so each answer is recorded and replayed.
- **The field children:** one per field the request carries, not per changed value, so the set is a pure function of the request.
  - **The children, in this order:** `field:title`, `field:notes`, `field:priority`, `field:deadline` (also for `clearDeadline`), `field:estimatedMinutes`, `field:confirmation`. Each is observed at the request's `expectedRevision` N.
  - **One projection:** they are taken in without projecting, then projected once with `forceRevision`. R1's `correct` always writes, so this is one R1 revision step even when no value changes.
  - **The deadline** is marked owner-corrected whenever the request sets or clears it, as R1 marks it.
  - **Then** R1's `task.corrected` audit event and `.taskChanged(material:)`.
- **The status:**
  - **Children by target:** `completed` gets a `status` child `task.complete`, `cancelled` gets `task.cancel`, and `open` gets `task.reopen` naming nothing, observed at N. The child depends on the target alone.
  - **In progress and blocked** have no R2 operation. They are R1's own states of an open task: R2's merge doesn't hold them, and the projection keeps them (`TaskProjection.status`).
    - **Who writes them:** the converter, with R1's `LisaTask.transition` on R1's record in the same transaction. It also writes an active task's return to open, after its reopen child.
    - **The revision map:** each such write records its revision there (`recordProjectionRevision`), so a later edit observed at it supersedes as R1's does. Harness v38 found this.
  - **R1's rules decide:** `TaskService.transition`'s principal check and `LisaTask.transition` decide against the corrected record.
    - A refusal answers R1's 409 with the correction committed and the status child `refused`, as R1 keeps its correction.
    - A target equal to the record's status makes no R1 call: no audit, no revision. Its child, if any, is taken in and changes nothing.
  - **After a transition:** R1's `task.<status>` audit event and its domain change.
- **Two protocol rules** (`docs/SYNC-PROTOCOL.md` §8):
  - **Empty notes:** `note.replaceObserved` may carry empty text. It then removes the notes it observes and adds none (R1's `notes: ""`).
  - **A reopen naming nothing:** `task.reopen` may name no action. It then reopens the terminal actions its observed coverage covers.
    - One committed after the horizon, or still pending, stays in effect. `TerminalActions` keeps commit positions, and `markCommitted` covers them.
    - A device's reopen that names actions is unchanged.
    - The v1 reopen names nothing because a child's body may not depend on current state. Core resolves its revision to a horizon at decision (D-69), and replicas fold with the served horizon.
- **Terminal replies for PATCH:** an expired body answers 200 with the current `TaskDTO` (`Lisa-Replayed: true`, `Lisa-Reply: current`), or 404 "This change was applied; the task was deleted afterwards.". `lisaCode` comes with M3-6d.
- **Known limits:**
  - A task the ledger doesn't hold, such as an R1 record from before the conversion, can't be corrected through the converter until migration records its origin (M9).
  - Notes longer than a note piece's budget need blobs (§8.3.3).
  - The ID mapping (`R1Identity`) needs UUID record IDs, which R1 generates.
- **Shown by M3 harness v38** (v37 was corrected before its first build and never built). Each PATCH, against R1's own path on a second host, gives R1's status, headers and body, but for the task's ID, at every step:
  - a correction of every field;
  - clearing the notes and the deadline;
  - a same-value correction, which takes a revision and marks the deadline;
  - a stale revision, an unknown task and invalid values, each recorded and replayed;
  - every status R1 allows, in turn;
  - a refused status after a correction, with the correction kept and the status child refused;
  - the same status, which changes nothing;
  - an edit after in-progress.

  A replica pulling Core's pages folds the reopen through its served horizon, with the same view as Core's.

## D-73 — Preferences as one register per key: the entity, the payloads and the merge (R2 M3-6b, run 20261124-r2-5462; plan §8.2.3, §8.3.1, §8.12.2)

- **The entity:** a preference is a register per key, not an owner item.
  - **Its entity ID** is the first 16 bytes of `SHA-256("lisa-preference-key-v1" ‖ 0x00 ‖ key)` (`PreferenceEntity`, LisaTrust). So every device, Core and every epoch name a key the same way.
  - **R1's record IDs play no part.** They are random, and a delete followed by a set changes them.
  - **Placement:** entity type `preference`, partition `preferences`.
- **The payloads** (`PreferenceOperationPayload`, `docs/SYNC-PROTOCOL.md` §8):
  - **The three types:** `preference.set {key, value}`, `preference.delete {key}` and `preference.confirm {key}`.
  - **Values:** typed `text`, `number`, `flag` or `list`.
    - A number travels as its shortest decimal text that reads back as the same finite value, and that text is its only accepted form, because canonical JSON carries integers only.
    - A list holds at most 256 strings, and the payload fits the type's value budget.
  - **A key** is 1–256 UTF-8 bytes without control characters. R1 accepts any key text and refuses unsupported keys itself (400). So a request's unsupported key is still a well-formed child, which Core refuses under R1's rule.
- **The merge** (`PreferenceMergeState`): one multi-value register of `value?`.
  - **Sets and deletes:** a set writes its value and a delete writes none, each replacing exactly the versions it observed. A delete therefore clears what it saw, and a later set re-creates the key, as R1's delete then set does. §8.3.1's dominating tombstone is for owner items, which a key isn't.
  - **Authority:** a model value never replaces an owner value and is kept as a suggestion.
  - **Confirmations:** a confirmation confirms the model-authority candidates it observed.
  - **The view:** the key is absent only when every survivor is a delete. Otherwise the shown value is the first surviving value in display order. Two or more survivors, a delete among them or not, are a conflict.
- **Step 2, done** (`f404e2c`–`44cb3ed`; harness v43):
  - Core's intake and fold, with the check that the entity ID matches the key;
  - the projection into R1's `Preference` record (`PreferenceProjection`);
  - the replica's fold;
  - partition `preferences`.

  R1's audit events come with the conversion.
- **Next (M3-6b):**
  - the conversion of `PATCH /v1/preferences`: `change:<index>` children, R1's stop at the first refusal, administrative holds, `legacy review` and `resolve`, and restricted siblings.
- **Shown by** M3 harness v41 (v40 was corrected before its first build and is kept, never built):
  - the canonical forms and round trips;
  - every decoding rule;
  - the entity IDs against Python's hashlib;
  - the merge cases, and one state and one view over all 720 orders of a representative set.

## D-74 — R1's `PATCH /v1/preferences` through the converter: R2-TRUST-05 at Core, what a converted child observes, and errors without caller text (R2 M3-6b, run 20261124-r2-5462; plan §8.12.2, §8.17; R2-TRUST-05)

- **The keys** (`PreferenceRules`, LisaOwnerData):
  - **Supported:** the 24 keys R1's `PreferenceMapping` maps. R1 refuses any other as "not a supported preference".
  - **Administrative** (R2-TRUST-05): R1's consequential keys. They are call escalation, the model endpoint and data sharing, the approved email addresses and phone number, email and call enablement, and time-sensitive notifications.
  - **Permitted:** supported and not administrative. Only these replicate (§8.17's "permitted preferences").
  - **Restricted:** the others and unsupported keys. A v1 request's change to one is a restricted sibling (§8.12.2). The plan's examples name the model settings and unsupported keys. The narrower reading of "permitted" restricts the approved recipients and the enablement keys too.
- **Core refuses a device's own preference operation** (`docs/SYNC-PROTOCOL.md` §8):
  - **The reasons:** `unsupported_key`; `administrative_key`, for a set, delete or confirm alike; `invalid_value`, from R1's own `validate`.
  - **No caller text:** neither the reason nor the hint names the key or the value.
  - **Legacy children** are Core-signed, so R1's checks in their conversion decide them instead.
  - **The replica** doesn't check yet; Core is the authority.
  - **The dependency:** LisaCoreLedger now depends on LisaOwnerData for R1's rules.
- **What a converted child observes:** R1's record of the key as Core found it when it decided the child (`resolveFoundRecord`). That is the record R1's `set`, `confirm` and delete act on.
  - **A record:** the horizon its revision reflects, from the projection map (D-69).
    - The conversion fails (500, nothing kept) when the record's revision isn't in the map.
    - Such a record was written outside Core: before migration, or by R1's inference, which isn't converted yet.
  - **An absent key:** every commit before the child. What is left of the key then is deletes, replaced writes and model suggestions, which R1's write replaces too.
  - **Why:** §8.12.2 gives a legacy child an observed set only for R1's `expectedRevision`.
    - Every confirm and delete has none, and neither does a set without a revision. Such a change would observe nothing.
    - Then a delete wouldn't remove the value, a confirm wouldn't confirm it, and 50 sets of one key wouldn't replace each other.
    - Once R1's check passes, the found record is the one at the request's `expectedRevision`. So for revision-checked sets the rule agrees with D-69.
    - A set's body still carries R1's revision when it is ≥ 1.
  - **Served:** Core records the horizon with the decision and serves it in `ChangeEntry.observedHorizon`, now allowed on every legacy preference child. Replicas fold with it (D-69's machinery).
  - **The consequence:** a concurrent value that R1's record didn't show, committed after the record's current revision, survives a v1 write as a conflict. Task edits behave the same under D-69.
- **The conversion** (`LegacyPreferenceRoutes`, LisaLegacyRequests; `convertUpdatePreferences`, LisaAPI):
  - **Inside the parent:** the body size, its decoding and the 1–50 changes, so their answers replay.
  - **Children:** `change:<index>` in request order, chained per key, so a child depends only on its immediate same-key predecessor.
    - **The set's IDs and digest** come from the discriminators alone (`LegacyChildPlan`).
    - **Each envelope** is encoded only when its child is taken in. R1 refuses a value over the operation's budget before it would have to be encoded.
  - **Each change in order,** against R1's records as the earlier changes left them:
    - R1's checks, in R1's order (`PreferenceService.set` and `confirm`, `DeletionService.delete`);
    - the child taken in;
    - the projection, written once, with `force` for a set or confirm (one R1 revision step each);
    - R1's audit event: `preference.set`, `preference.confirmed` or `data.deleted`.
  - **The first refusal** stops the request:
    - the earlier children stay applied;
    - the refused child is `refused`, and the rest are `not_reached`;
    - refused and unreached children are never taken in, so their bodies, a canary key among them, never reach the ledger.
  - **The answer:** 200 with R1's full list, read from R1's records in the conversion's transaction, or the refusal, recorded.
  - **Domain changes:** one `preferenceChanged(key)` per applied change, propagated after the commit.
  - **The terminal reply** after the body expires: §8.12.2's 409, "This change was applied; its reply is no longer available. Reload to see current values." `lisaCode` comes with M3-6d.
- **Errors without caller text** (§8.12.2): R1's status and code, and a template that names the position, counted from 0 as `legacyParent.index` is:
  - `changes[i].key is not a supported preference`, with `field: "changes[i].key"`;
  - `changes[i].value` followed by R1's reason, with `field: "changes[i].value"`. R1's one reason that names the caller's token becomes "has an unknown weekday";
  - `changes[i] can be changed only by the owner on the host`, and `changes[i] can be deleted only by the owner on the host`;
  - `changes[i] names a preference that does not exist`;
  - `changes[i] changed since it was read; reload it and try again`, with R1's current revision.
- **Left for the next part** (M3-6b step 3b):
  - An owner-scope request that reaches an administrative key fails the conversion (500, nothing kept). Holds, decision tokens, `legacy review` and `resolve` lift this.
  - A change R1 would apply to a restricted key, such as a device's confirm of an administrative key, fails it the same way. Restricted siblings and their redacted receipts lift this.
  - R1's own checks run first, so an invalid value is still R1's 400 at once.
  - `LisaHost` doesn't enable the converter.
- **Shown by** M3 harness v45, 10/10 on its first build, against R1's own path on a second host, and regression package v26. v44 was corrected before its first build and is kept, never built (`docs/VERIFICATION-SCENARIOS.md`, M3-6b's third step).
